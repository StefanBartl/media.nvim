-- The mpv argument order for audio-only playback.
--
-- Pure function, same reasoning as frame_args_spec / frames_args_spec: an
-- argument in the wrong position (or a missing `--no-video`) is invisible
-- until it is the one file in months where a video window pops up behind the
-- terminal instead of sound coming out of the speakers. The IPC round trip
-- itself needs a real mpv and is not what this suite is for — see
-- `media.core.audio`'s module header for why that is a whole player and not
-- a decoder in the first place.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local audio = require("media.core.audio")

  local argv = audio.args({
    mpv = "mpv",
    path = "/tmp/clip.mp4",
    sock = "/tmp/media.nvim/mpv-1-2.sock",
    at = 12.5,
  })

  H.eq(argv[1], "mpv", "the binary leads")
  H.ok(H.index_of(argv, "--no-video"), "audio only — this is not the video hover's picture")
  H.ok(H.index_of(argv, "--no-terminal"), "nothing here reads mpv's own terminal controls")
  H.ok(
    H.index_of(argv, "--input-ipc-server=/tmp/media.nvim/mpv-1-2.sock"),
    "the socket this session will connect to"
  )
  H.ok(H.index_of(argv, "--start=12.5"), "the offset is passed through, not rounded")
  H.eq(argv[#argv], "/tmp/clip.mp4", "the file is last, like every other argv in this plugin")
  H.before(argv, "--start=12.5", "/tmp/clip.mp4", "the seek is a flag before the file, not after")

  -- No offset, no `--start`: `at = nil` and `at = 0` both mean "from the
  -- beginning", which mpv already does without being told.
  local from_start = audio.args({ mpv = "mpv", path = "/tmp/clip.mp4", sock = "/tmp/s.sock" })
  local has_start = false
  for _, a in ipairs(from_start) do
    if a:match("^%-%-start=") then has_start = true end
  end
  H.falsy(has_start, "no offset given, no --start")

  local at_zero = audio.args({ mpv = "mpv", path = "/tmp/clip.mp4", sock = "/tmp/s.sock", at = 0 })
  has_start = false
  for _, a in ipairs(at_zero) do
    if a:match("^%-%-start=") then has_start = true end
  end
  H.falsy(has_start, "at = 0 is the beginning, not a seek")
end
