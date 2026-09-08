-- The ffmpeg argument order for a *run* of stills, and the naming of its
-- outputs.
--
-- Pure functions, for the same reason `frame_args_spec` gives: the decisions
-- that matter here are invisible in the rendered PNGs. Two of them would each
-- produce a plausible-looking wrong result rather than an error — a filter
-- chain in the wrong order (the scaler running on every decoded frame instead
-- of the twelve that survive) and an output pattern that does not match the
-- paths the caller is handed back (a run that renders and then reports
-- nothing).
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local frames = require("media.core.frames")

  -- ── Argument order ───────────────────────────────────────────────────────
  local argv = frames.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/clip.mp4",
    pattern = "/tmp/cache/abc-%03d.png",
    from = 12,
    count = 24,
    fps = 12,
    width = 320,
  })

  H.eq(argv[1], "ffmpeg", "the binary leads")
  H.ok(H.index_of(argv, "-nostdin"), "stdin is closed, or ffmpeg can block on it forever")
  -- Same seek argument as `frame`: as an input option it jumps to a keyframe,
  -- as an output option it decodes everything before the offset first.
  H.before(argv, "-ss", "-i", "the seek is an input option")
  H.eq(argv[#argv], "/tmp/cache/abc-%03d.png", "the output pattern is last")
  H.eq(argv[#argv - 1], "-y", "and is overwritten without a prompt")

  local vf = argv[H.index_of(argv, "-vf") + 1]
  H.eq(vf, "fps=12,scale=320:-2", "one filter chain, fps before the scaler")
  H.eq(argv[H.index_of(argv, "-frames:v") + 1], "24", "the run length is the frame count")

  -- Without a width there is no scaler, and the chain is still valid.
  local no_scale = frames.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/clip.mp4",
    pattern = "/tmp/cache/abc-%03d.png",
    count = 4,
    fps = 8,
  })
  H.eq(no_scale[H.index_of(no_scale, "-vf") + 1], "fps=8", "no width, no scale filter")
  H.falsy(H.index_of(no_scale, "-ss"), "no offset, no seek")

  -- ── Output naming ────────────────────────────────────────────────────────
  --
  -- The pattern and the path list have to agree: ffmpeg writes what the
  -- pattern says, and the caller is handed the list. A mismatch renders the
  -- run correctly and then reports that nothing was written.
  local pattern, outs = frames.outputs("/tmp/cache/deadbeef.png", 3)
  H.eq(pattern, "/tmp/cache/deadbeef-%03d.png", "the pattern is ffmpeg's own numbering")
  H.eq(#outs, 3, "one path per requested frame")
  H.eq(outs[1], "/tmp/cache/deadbeef-001.png", "zero-padded, one-based, like ffmpeg")
  H.eq(outs[3], "/tmp/cache/deadbeef-003.png", "in order")
  H.eq(
    outs[1],
    pattern:gsub("%%03d", "001"),
    "the first path is exactly what the pattern expands to"
  )

  -- The cache key has to separate two runs that differ only in run parameters,
  -- or the second is served the first one's frames -- forever, since entries
  -- are keyed by content and never expire.
  local cache = require("media.core.cache")
  local a = cache.key("frames", "/tmp/clip.mp4", 111, { "0", 24, 12, 320 })
  local b = cache.key("frames", "/tmp/clip.mp4", 111, { "0", 24, 24, 320 })
  local c = cache.key("frame", "/tmp/clip.mp4", 111, { "0", 24, 12, 320 })
  H.ok(a ~= b, "a different fps is a different run")
  H.ok(a ~= c, "a run and a single still do not collide")
end
