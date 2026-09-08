-- Reading ffprobe's JSON, without ffprobe.
--
-- `need-check-nil` is off for this file (`NEW-41`): the body of a test is its
-- own guard — a nil where a record is expected fails the next assertion with a
-- better message than a type check would produce, and checking each access
-- individually only cements the noise.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local probe = require("media.core.probe")

  -- ── The ordinary case ────────────────────────────────────────────────────
  local p = probe.from_ffprobe("/tmp/clip.mp4", H.ffprobe_video())
  H.eq(p.path, "/tmp/clip.mp4", "path is carried through")
  H.eq(p.width, 1920, "width")
  H.eq(p.height, 1080, "height")
  H.eq(p.video_codec, "h264", "video codec")
  H.eq(p.audio_codec, "aac", "audio codec")
  H.eq(p.channels, 2, "channels")
  H.eq(p.sample_rate, 48000, "sample rate is an integer, not the string ffprobe sent")
  H.eq(p.size, 104857600, "size")
  H.ok(p.has_video, "has_video")
  H.ok(p.has_audio, "has_audio")
  H.falsy(p.has_cover, "an ordinary video has no cover art")
  H.ok(math.abs(p.duration - 272.36) < 0.001, "duration is a number")
  H.ok(math.abs(p.fps - 29.97) < 0.01, "fps comes from the rational, not from rounding")

  -- ── Rotation swaps the reported dimensions ───────────────────────────────
  -- The failure this prevents: a portrait phone video sized into a landscape
  -- window, because the stored pair was believed over the display matrix.
  local rotated = probe.from_ffprobe(
    "/tmp/phone.mp4",
    H.ffprobe_video({ side_data_list = { { rotation = -90 } } })
  )
  H.eq(rotated.width, 1080, "a 90-degree rotation swaps width")
  H.eq(rotated.height, 1920, "a 90-degree rotation swaps height")
  H.eq(rotated.rotation, -90, "the rotation itself is reported as stored")

  local tagged = probe.from_ffprobe("/tmp/old.mp4", H.ffprobe_video({ tags = { rotate = "270" } }))
  H.eq(tagged.width, 1080, "the legacy `rotate` tag is read too")

  local upright = probe.from_ffprobe(
    "/tmp/flip.mp4",
    H.ffprobe_video({ side_data_list = { { rotation = 180 } } })
  )
  H.eq(upright.width, 1920, "180 degrees does not swap the axes")

  -- ── Cover art is not a video ─────────────────────────────────────────────
  -- The failure this prevents: every tagged mp3 in a library looking like a
  -- one-frame video, and a seek into it writing no file.
  local mp3 = probe.from_ffprobe("/tmp/song.mp3", {
    format = { format_name = "mp3", duration = "213.5", size = "5242880" },
    streams = {
      { codec_type = "audio", codec_name = "mp3", channels = 2, sample_rate = "44100" },
      {
        codec_type = "video",
        codec_name = "mjpeg",
        width = 600,
        height = 600,
        disposition = { attached_pic = 1 },
      },
    },
  })
  H.falsy(mp3.has_video, "attached cover art is not moving picture")
  H.ok(mp3.has_cover, "but it is reported as cover art")
  H.ok(mp3.has_audio, "and the audio stream is still seen")
  H.eq(mp3.width, 600, "the cover's dimensions are still worth having")

  -- ── Missing answers stay missing ─────────────────────────────────────────
  local bare = probe.from_ffprobe("/tmp/stream.ts", {
    format = { format_name = "mpegts" },
    streams = { { codec_type = "video", codec_name = "h264", avg_frame_rate = "0/0" } },
  })
  H.eq(bare.duration, nil, "no duration anywhere means nil, not zero")
  H.eq(bare.fps, nil, "`0/0` is ffprobe's way of saying it does not know")
  H.eq(bare.width, nil, "a stream without dimensions reports none")
  H.ok(bare.has_video, "it is still a video stream")

  -- A container without a duration falls back to the stream's.
  local from_stream = probe.from_ffprobe("/tmp/cut.mkv", {
    format = { format_name = "matroska" },
    streams = { { codec_type = "video", codec_name = "h264", duration = "61.2" } },
  })
  H.ok(math.abs(from_stream.duration - 61.2) < 0.001, "stream duration is the fallback")
end
