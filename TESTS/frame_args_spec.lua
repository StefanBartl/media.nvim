-- The ffmpeg argument order, and the offset arithmetic behind it.
--
-- Both are pure functions for exactly this reason: the decisions worth
-- asserting here (`-ss` before `-i`, a percentage against a duration, the clamp
-- at the end of a file) are invisible in a rendered PNG and need no ffmpeg to
-- check.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local frame = require("media.core.frame")

  -- ── Argument order ───────────────────────────────────────────────────────
  local argv = frame.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/clip.mp4",
    out = "/tmp/out.png",
    at = 27.5,
    width = 800,
  })

  -- The whole performance story of this plugin: as an input option `-ss` is a
  -- seek, as an output option it is a decode of everything before the offset.
  -- On a two-hour file that is the difference between 0.2 s and half a minute.
  H.before(argv, "-ss", "-i", "the seek is an input option")
  H.eq(argv[1], "ffmpeg", "the binary leads")
  H.ok(H.index_of(argv, "-nostdin"), "stdin is closed, or ffmpeg can block on it forever")
  H.eq(argv[#argv], "/tmp/out.png", "the output path is last")
  H.eq(argv[#argv - 1], "-y", "and is overwritten without a prompt")

  local vf = H.index_of(argv, "-vf")
  H.ok(vf, "a width means a scale filter")
  H.eq(argv[vf + 1], "scale=800:-2", "the height follows the aspect ratio, rounded even")

  local frames = H.index_of(argv, "-frames:v")
  H.eq(argv[frames + 1], "1", "exactly one frame")

  -- ── No width, no filter ──────────────────────────────────────────────────
  local unscaled = frame.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/clip.mp4",
    out = "/tmp/out.png",
    at = 1,
  })
  H.falsy(H.index_of(unscaled, "-vf"), "without a width there is nothing to scale")

  -- ── Cover art is mapped, not seeked ──────────────────────────────────────
  -- The failure this prevents: seeking ten percent into an album cover, which
  -- has one frame at offset zero, and writing no file at all.
  local cover = frame.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/song.mp3",
    out = "/tmp/cover.png",
    at = 21.3,
    cover = true,
  })
  H.falsy(H.index_of(cover, "-ss"), "cover art is never seeked, even when an offset was passed")
  H.before(cover, "-map", "-frames:v", "the video stream is selected explicitly")
  local map = H.index_of(cover, "-map")
  H.eq(cover[map + 1], "0:v", "because a tagged file usually leads with its audio stream")

  -- ── Offsets ──────────────────────────────────────────────────────────────
  local at, err = frame.resolve_at(12, 300)
  H.eq(err, nil, "a plain number needs nothing")
  H.eq(at, 12, "and is seconds")

  at = frame.resolve_at("10%", 300)
  H.ok(math.abs(at - 30) < 0.001, "a percentage is taken of the duration")

  at = frame.resolve_at("00:01:23", nil)
  H.eq(at, "00:01:23", "a timestamp is handed to ffmpeg untouched")

  at, err = frame.resolve_at("10%", nil)
  H.eq(at, nil, "a percentage without a duration cannot be resolved")
  H.ok(err, "and says so rather than guessing")

  -- The clamp: a percentage of a duration ffprobe rounded up lands past the
  -- last frame, ffmpeg writes nothing, and the failure reads as a broken
  -- renderer instead of an offset one frame too far.
  at = frame.resolve_at("100%", 10)
  H.ok(at < 10, "an offset at or past the end is pulled back inside the file")
  H.ok(at > 9, "but only just — the still should still be from the end")

  at = frame.resolve_at(-5, 10)
  H.eq(at, 0, "a negative offset is the start of the file")
end
