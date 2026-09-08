---@module 'media.ui'
---@brief Turning this plugin's two answers into something a person can look at.
---@description
--- The commands need somewhere to put a result, and there are exactly two kinds
--- of result: a record and a picture. This module is the whole of that, kept
--- apart from `core/` because none of it is part of the API another plugin
--- consumes — a consumer wants the PNG path, not a window around it.
---
--- **Neither half is a hard dependency.** The scratch window comes from
--- `lib.nvim` and degrades to a notification; the picture goes to `images.nvim`
--- and degrades to the system image viewer, and then to printing the path. Each
--- step down is still an answer to what the user asked, which is the bar for
--- letting an optional dependency be optional.

local M = {}

---@internal
---@param n number|nil
---@return string
local function human_bytes(n)
  if not n then return "?" end
  local ok, fmt = pcall(require, "lib.lua.strings.format")
  if ok and fmt and fmt.format_bytes then return fmt.format_bytes(n) end
  local units = { "B", "KB", "MB", "GB", "TB" }
  local i = 1
  while n >= 1024 and i < #units do
    n = n / 1024
    i = i + 1
  end
  return (i == 1 and "%d %s" or "%.1f %s"):format(n, units[i])
end

--- A duration as `h:mm:ss` or `m:ss`.
---
--- Hours are dropped when there are none rather than padded to `0:04:32`,
--- because the string is read at a glance next to a filename and a leading zero
--- there is one more thing to parse.
---@param seconds number|nil
---@return string
function M.duration(seconds)
  if not seconds or seconds < 0 then return "?" end
  local total = math.floor(seconds + 0.5)
  local h = math.floor(total / 3600)
  local m = math.floor((total % 3600) / 60)
  local s = total % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end

--- The one-line summary a consumer puts in a border or a status area.
---
--- Pure, and public, because it is the piece other plugins actually want: a
--- hover float has room for one line, and every consumer writing its own would
--- produce a different word for the same file.
---@param probe Media.Probe
---@return string
function M.summary(probe)
  local parts = {}
  if probe.width and probe.height then
    parts[#parts + 1] = ("%dx%d"):format(probe.width, probe.height)
  end
  if probe.duration then parts[#parts + 1] = M.duration(probe.duration) end
  if probe.video_codec then
    parts[#parts + 1] = probe.video_codec
  elseif probe.audio_codec then
    parts[#parts + 1] = probe.audio_codec
  end
  if probe.size then parts[#parts + 1] = human_bytes(probe.size) end
  return table.concat(parts, " · ")
end

--- The full record, one field per line.
---
--- Pure so the spec can assert it without ffmpeg: what has to hold is that a
--- field ffprobe could not answer is left out rather than printed as "nil",
--- which is the failure this shape exists to prevent.
---@param probe Media.Probe
---@return string[]
function M.describe(probe)
  local lines = { vim.fn.fnamemodify(probe.path, ":t"), "" }

  ---@param label string
  ---@param value string|number|nil
  local function row(label, value)
    if value ~= nil and value ~= "" then
      lines[#lines + 1] = ("  %-12s %s"):format(label, tostring(value))
    end
  end

  row("container", probe.container)
  row("duration", probe.duration and M.duration(probe.duration) or nil)
  row("size", probe.size and human_bytes(probe.size) or nil)
  row("bitrate", probe.bitrate and ("%d kbit/s"):format(math.floor(probe.bitrate / 1000)) or nil)

  if probe.has_video or probe.has_cover then
    lines[#lines + 1] = ""
    lines[#lines + 1] = probe.has_video and "  video" or "  cover art"
    row("codec", probe.video_codec)
    row(
      "resolution",
      probe.width and probe.height and ("%dx%d"):format(probe.width, probe.height) or nil
    )
    row("fps", probe.fps and ("%.3f"):format(probe.fps) or nil)
    -- Only when there is one: "rotation 0" on every landscape video is noise,
    -- and on the one file where it matters the reader needs to see it.
    row("rotation", probe.rotation and probe.rotation ~= 0 and (probe.rotation .. "°") or nil)
  end

  if probe.has_audio then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "  audio"
    row("codec", probe.audio_codec)
    row("channels", probe.channels)
    row("sample rate", probe.sample_rate and (probe.sample_rate .. " Hz") or nil)
  end

  return lines
end

---@internal
---@param lines string[]
---@param title string
---@return nil
local function scratch(lines, title)
  local ok, make_scratch = pcall(require, "lib.nvim.window.make_scratch")
  if ok then
    make_scratch({
      lines = lines,
      filetype = "text",
      title = title,
      title_pos = "center",
      width = 0.5,
      height = 0.5,
      wo = { wrap = false },
      nice_quit = true,
    })
    return
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = title })
end

--- Probe `path` and show the record.
---@param path string
---@return nil
function M.show_probe(path)
  require("media.core.probe").probe(path, function(probe, err)
    if not probe then
      vim.notify(err or "probe failed", vim.log.levels.ERROR, { title = "media.nvim" })
      return
    end
    scratch(M.describe(probe), " media: " .. vim.fn.fnamemodify(path, ":t") .. " ")
  end)
end

--- Show a rendered PNG, by whatever means are installed.
---@param png string
---@return nil
function M.show_image(png)
  local ok_images, images = pcall(require, "images")
  if ok_images and type(images.show) == "function" then
    images.show(png)
    return
  end

  local ok_open, open_default = pcall(require, "lib.nvim.cross.open_default")
  if ok_open and open_default(png) then return end

  -- The last rung is still an answer: the file exists, it is a PNG, and the
  -- path is copyable. Silently doing nothing here would look like the render
  -- failed, which it did not.
  vim.notify(png, vim.log.levels.INFO, { title = "media.nvim" })
end

return M
