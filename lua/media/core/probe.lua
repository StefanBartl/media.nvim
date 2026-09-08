---@module 'media.core.probe'
---@brief What a media file is, according to `ffprobe`.
---@description
--- One process, one JSON document, one flat record. The flattening is the
--- point: ffprobe's output is a container format plus an array of streams, and
--- every consumer that has ever wanted it wanted the four or five numbers
--- underneath — how long, how big, which codec, is there a picture. Leaving
--- that to the caller means every caller reimplements the same three
--- traversals, and the interesting one (rotation) gets reimplemented wrong.
---
--- **Rotation is applied here, and that is not cosmetic.** A video recorded on
--- a phone held upright stores 1920x1080 frames plus a 90-degree rotation, and
--- is 1080x1920 on screen. A consumer that sizes a window from the stored pair
--- draws a landscape box around a portrait picture. `ffmpeg` auto-rotates on
--- decode, so the still produced by `media.core.frame` is already upright —
--- reporting the stored pair here would make the two halves of this plugin
--- disagree about the same file.
---
--- **An mp3 with cover art has a video stream.** ffprobe says so truthfully,
--- and taking it at face value makes every tagged music file look like a video
--- with one frame. The `attached_pic` disposition is what separates them, so
--- `has_video` means "there is moving picture here" and `has_cover` means
--- "there is one still, and it is the album art" — which is worth showing, just
--- not worth seeking into.

local M = {}

local uv = vim.uv or vim.loop

---@type table<string, { mtime: integer, probe: Media.Probe }>
local cache = {}

---@type table<string, (fun(probe: Media.Probe|nil, err: string|nil))[]>
local inflight = {}

---@internal
---@param path string
---@return integer|nil
local function mtime_of(path)
  local stat = uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or nil
end

---@internal
--- ffprobe reports every number as a string, and "N/A" for the ones it could
--- not determine — which `tonumber` turns into nil on its own, so the only
--- thing this adds is the type guard.
---@param v any
---@return number|nil
local function num(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

---@internal
---@param v any
---@return integer|nil
local function int(v)
  local n = num(v)
  return n and math.floor(n) or nil
end

---@internal
--- Frame rates arrive as the rational `"30000/1001"`, because that is what they
--- are — 29.97 is a rounding of it, not the value. A zero denominator is
--- ffprobe's way of saying "no answer", and appears for still images and for
--- streams whose rate could not be derived.
---@param rational any
---@return number|nil
local function fps_of(rational)
  if type(rational) ~= "string" then return nil end
  local n, d = rational:match("^(%d+)/(%d+)$")
  if not n then return tonumber(rational) end
  n, d = tonumber(n), tonumber(d)
  if not n or not d or d == 0 or n == 0 then return nil end
  return n / d
end

---@internal
--- Rotation lives in two places and neither is guaranteed: modern files carry a
--- display-matrix side-datum on the stream, older ones a `rotate` tag. Both are
--- read, side data first, because a file that has both had the tag written by
--- whatever produced it and the side datum by whatever last transformed it.
---@param stream table
---@return integer|nil degrees
local function rotation_of(stream)
  local list = stream.side_data_list
  if type(list) == "table" then
    for _, side in ipairs(list) do
      local rot = num(side.rotation)
      if rot then return math.floor(rot) end
    end
  end
  local tags = stream.tags
  if type(tags) == "table" then
    local rot = num(tags.rotate) or num(tags.Rotate)
    if rot then return math.floor(rot) end
  end
  return nil
end

---@internal
--- Turn ffprobe's JSON into the flat record. Split out from the run so it can
--- be tested against a captured document without ffmpeg installed anywhere —
--- the rotation and cover-art branches above are exactly the kind that are
--- wrong until something asserts them, and neither needs a real file.
---@param path string
---@param doc table decoded ffprobe output
---@return Media.Probe
function M.from_ffprobe(path, doc)
  local format = type(doc.format) == "table" and doc.format or {}
  local streams = type(doc.streams) == "table" and doc.streams or {}

  ---@type Media.Probe
  local probe = {
    path = path,
    container = type(format.format_name) == "string" and format.format_name or nil,
    duration = num(format.duration),
    size = int(format.size),
    bitrate = int(format.bit_rate),
    has_video = false,
    has_audio = false,
    has_cover = false,
  }

  for _, stream in ipairs(streams) do
    local kind = stream.codec_type
    local disposition = type(stream.disposition) == "table" and stream.disposition or {}

    if kind == "video" and not probe.width then
      local width, height = int(stream.width), int(stream.height)
      local rotation = rotation_of(stream)

      if rotation and math.abs(rotation) % 180 == 90 then
        width, height = height, width
      end

      probe.width = width
      probe.height = height
      probe.rotation = rotation
      probe.video_codec = type(stream.codec_name) == "string" and stream.codec_name or nil

      if disposition.attached_pic == 1 then
        probe.has_cover = true
      else
        probe.has_video = true
        probe.fps = fps_of(stream.avg_frame_rate) or fps_of(stream.r_frame_rate)
        -- A stream duration is the fallback for a container that reports none,
        -- which is the normal shape of a raw stream (`.ts`) and of a file whose
        -- header was never rewritten after a hard cut.
        probe.duration = probe.duration or num(stream.duration)
      end
    elseif kind == "audio" and not probe.audio_codec then
      probe.has_audio = true
      probe.audio_codec = type(stream.codec_name) == "string" and stream.codec_name or nil
      probe.channels = int(stream.channels)
      probe.sample_rate = int(stream.sample_rate)
      probe.duration = probe.duration or num(stream.duration)
    end
  end

  return probe
end

--- What is already known about `path`, without starting anything.
---
--- Public because a consumer drawing a window wants to draw it *now* if it can:
--- the second hover over the same file in one session has the answer already,
--- and a synchronous peek is the difference between a window that appears
--- filled and one that appears empty and fills in.
---@param path string
---@return Media.Probe|nil
function M.cached(path)
  local entry = cache[path]
  if not entry then return nil end
  if entry.mtime ~= mtime_of(path) then
    cache[path] = nil
    return nil
  end
  return entry.probe
end

--- Ask ffprobe about `path`.
---
--- The callback runs exactly once, always on the main loop (`vim.schedule`), so
--- it may touch the Neovim API — which every consumer of this does, and getting
--- it wrong produces the `E5560` that only shows up on the slow path.
---
--- **A cache hit still calls back asynchronously.** A function that is
--- sometimes synchronous is the harder contract to write against: the caller
--- would have to be correct both when the callback runs before its own next
--- line and when it runs after.
---@param path string
---@param callback fun(probe: Media.Probe|nil, err: string|nil): nil
---@return nil
function M.probe(path, callback)
  if type(path) ~= "string" or path == "" then
    vim.schedule(function()
      callback(nil, "no path given")
    end)
    return
  end

  local hit = M.cached(path)
  if hit then
    vim.schedule(function()
      callback(hit, nil)
    end)
    return
  end

  local waiting = inflight[path]
  if waiting then
    waiting[#waiting + 1] = callback
    return
  end
  inflight[path] = { callback }

  ---@param probe Media.Probe|nil
  ---@param err string|nil
  local function finish(probe, err)
    local waiters = inflight[path] or {}
    inflight[path] = nil
    vim.schedule(function()
      for _, cb in ipairs(waiters) do
        cb(probe, err)
      end
    end)
  end

  local ffprobe = require("media.core.bin").find("ffprobe")
  if not ffprobe then
    finish(nil, "ffprobe not found — install ffmpeg, or set `bin.ffprobe`")
    return
  end

  local stat = uv.fs_stat(path)
  if not stat then
    finish(nil, "no such file: " .. path)
    return
  end

  local argv = {
    ffprobe,
    "-v",
    "error",
    "-hide_banner",
    "-print_format",
    "json",
    "-show_format",
    "-show_streams",
    path,
  }

  local timeout = require("media.config").get().timeout_ms

  vim.system(argv, { text = true, timeout = timeout }, function(result)
    if result.code ~= 0 then
      local stderr = (result.stderr or ""):gsub("%s+$", "")
      finish(nil, stderr ~= "" and stderr or ("ffprobe exited with " .. tostring(result.code)))
      return
    end

    local ok, doc = pcall(vim.json.decode, result.stdout or "")
    if not ok or type(doc) ~= "table" then
      finish(nil, "ffprobe produced no readable JSON")
      return
    end

    local probe = M.from_ffprobe(path, doc)
    cache[path] = { mtime = stat.mtime and stat.mtime.sec or 0, probe = probe }
    finish(probe, nil)
  end)
end

--- Drop everything remembered about probed files.
---@return nil
function M.clear()
  cache = {}
end

return M
