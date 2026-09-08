-- The contact sheet's filter chain.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local sheet = require("media.core.sheet")

  local argv = sheet.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/film.mkv",
    out = "/tmp/sheet.png",
    rows = 3,
    cols = 4,
    width = 1200,
    margin = 4,
    duration = 272.36,
  })

  local vf = H.index_of(argv, "-vf")
  H.ok(vf, "there is a filter chain")
  local filter = argv[vf + 1]

  -- Twelve tiles spread over the running time — stated in seconds, not in
  -- decoded frames, so a 25 fps clip and a 60 fps clip of the same length are
  -- sampled the same way.
  H.match(filter, "^fps=12/272%.360000", "the rate is tiles over duration")
  H.match(filter, "tile=4x3", "columns before rows, as the tile filter reads them")
  H.match(filter, "margin=4", "tiles are separated")

  -- A tile is derived from the requested sheet width, minus the margins that
  -- sit outside the tiles: (1200 - 4*5) / 4 = 295.
  H.match(filter, "scale=295:%-2", "the tile width comes out of the sheet width")

  H.eq(argv[#argv], "/tmp/sheet.png", "the output path is last")
  H.falsy(H.index_of(argv, "-skip_frame"), "a four-and-a-half-minute file is decoded in full")

  -- ── Long files are sampled from keyframes ────────────────────────────────
  -- Without this a two-hour film decodes every frame to throw all but twelve
  -- away, which is minutes of work for one picture.
  local long = sheet.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/film.mkv",
    out = "/tmp/sheet.png",
    rows = 3,
    cols = 4,
    width = 1200,
    margin = 4,
    duration = 7200,
    keyframes_only = true,
  })
  H.before(long, "-skip_frame", "-i", "it is a decoder flag, so it precedes the input")
  local skip = H.index_of(long, "-skip_frame")
  H.eq(long[skip + 1], "nokey", "everything but keyframes is thrown away before decode")

  -- ── The duration never reaches ffmpeg in exponent notation ───────────────
  -- `tostring(1e-05)` is "1e-05", which is not a rational, and it takes the
  -- whole filter graph down rather than just the rate.
  local tiny = sheet.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/blip.mp4",
    out = "/tmp/sheet.png",
    rows = 1,
    cols = 2,
    width = 400,
    margin = 0,
    duration = 0.00001,
  })
  local tiny_filter = tiny[H.index_of(tiny, "-vf") + 1]
  H.falsy(tiny_filter:find("e-", 1, true), "the duration is formatted, not stringified")
end
