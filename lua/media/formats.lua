---@module 'media.formats'
---@brief Which extensions this plugin claims, and whether they carry pictures.
---@description
--- **Extension, not content.** Every caller here asks the question while a
--- cursor rests on a path or a selection moves through a list — a hundred times
--- a minute, against files that may not exist. Opening each candidate to sniff
--- its header is the wrong cost at that moment, and the wrong answer is cheap
--- to recover from: the worst case of a false positive is one `ffprobe` that
--- reports nothing, and `probe` already has to survive that.
---
--- **Why video and audio are separate lists rather than one flag.** They differ
--- in exactly the thing consumers branch on: a video has a frame to show, an
--- audio file has only something to say. `.mkv` and `.ogg` are the reason the
--- distinction cannot be derived — both are containers that legally hold
--- either, and the extension is a convention about what people usually put in
--- them. `probe`'s `has_video`/`has_audio` are the truthful answer; these lists
--- are the cheap guess made before a process is worth starting.

local M = {}

---@type table<string, true>
local VIDEO = {
  mp4 = true,
  m4v = true,
  mkv = true,
  mov = true,
  avi = true,
  webm = true,
  wmv = true,
  flv = true,
  mpg = true,
  mpeg = true,
  m2v = true,
  ts = true,
  mts = true,
  m2ts = true,
  ogv = true,
  ["3gp"] = true,
  vob = true,
  divx = true,
}

---@type table<string, true>
local AUDIO = {
  mp3 = true,
  wav = true,
  flac = true,
  ogg = true,
  oga = true,
  opus = true,
  m4a = true,
  aac = true,
  wma = true,
  aiff = true,
  aif = true,
  mka = true,
  ape = true,
  wv = true,
  amr = true,
}

--- The lowercased extension of `path`, or nil.
---
--- Trailing whitespace is tolerated because the callers that matter hand over a
--- path lifted out of a buffer — a markdown link, a `<cfile>` — and a stray
--- space at the end is the normal shape of that, not a defect worth rejecting.
---@param path string|nil
---@return string|nil
function M.extension(path)
  if type(path) ~= "string" or path == "" then return nil end
  local ext = path:match("%.([%w]+)%s*$")
  return ext and ext:lower() or nil
end

---@param path string|nil
---@return boolean
function M.is_video(path)
  local ext = M.extension(path)
  return ext ~= nil and VIDEO[ext] == true
end

---@param path string|nil
---@return boolean
function M.is_audio(path)
  local ext = M.extension(path)
  return ext ~= nil and AUDIO[ext] == true
end

---@param path string|nil
---@return boolean
function M.is_media(path)
  return M.is_video(path) or M.is_audio(path)
end

--- Every extension this plugin claims, sorted.
---
--- Sorted and public because both consumers want an order: the `:checkhealth`
--- line that prints what is claimed, and the completion that offers media files
--- first. A set cannot be printed twice the same way.
---@return string[] video
---@return string[] audio
function M.known()
  local video, audio = {}, {}
  for ext in pairs(VIDEO) do
    video[#video + 1] = ext
  end
  for ext in pairs(AUDIO) do
    audio[#audio + 1] = ext
  end
  table.sort(video)
  table.sort(audio)
  return video, audio
end

return M
