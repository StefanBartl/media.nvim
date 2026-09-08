-- The strings a consumer puts in a border, and the record behind them.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local ui = require("media.ui")

  H.eq(ui.duration(0), "0:00", "zero is a duration too")
  H.eq(ui.duration(61), "1:01", "under an hour, no hour field")
  H.eq(ui.duration(3661), "1:01:01", "over an hour, one")
  H.eq(ui.duration(nil), "?", "an unknown duration says so")

  ---@type Media.Probe
  local probe = {
    path = "/tmp/A Long Film.mkv",
    container = "matroska,webm",
    duration = 272.36,
    size = 104857600,
    bitrate = 3080000,
    has_video = true,
    has_audio = true,
    has_cover = false,
    width = 1920,
    height = 1080,
    fps = 29.97,
    video_codec = "h264",
    audio_codec = "aac",
    channels = 2,
    sample_rate = 48000,
  }

  local summary = ui.summary(probe)
  H.match(summary, "1920x1080", "the summary leads with the dimensions")
  H.match(summary, "4:32", "and carries the running time")
  H.match(summary, "h264", "and the codec")

  local lines = ui.describe(probe)
  local text = table.concat(lines, "\n")
  H.eq(lines[1], "A Long Film.mkv", "the record is headed by the file name, not the path")
  H.match(text, "video", "the video section is there")
  H.match(text, "audio", "and the audio one")
  H.falsy(text:find("rotation"), "an unrotated file says nothing about rotation")

  -- The failure this prevents: a field ffprobe could not answer printed as the
  -- literal string "nil", which has happened in every plugin that formatted a
  -- record without deciding what absence looks like.
  ---@type Media.Probe
  local sparse = {
    path = "/tmp/stream.ts",
    has_video = true,
    has_audio = false,
    has_cover = false,
  }
  local sparse_text = table.concat(ui.describe(sparse), "\n")
  H.falsy(sparse_text:find("nil"), "nothing unknown is printed as nil")
  H.falsy(sparse_text:find("audio"), "and a section with nothing in it is left out")

  ---@type Media.Probe
  local rotated = {
    path = "/tmp/phone.mp4",
    has_video = true,
    has_audio = false,
    has_cover = false,
    width = 1080,
    height = 1920,
    rotation = -90,
  }
  H.match(table.concat(ui.describe(rotated), "\n"), "rotation", "a rotated file does mention it")
end
