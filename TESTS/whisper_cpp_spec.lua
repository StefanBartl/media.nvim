-- whisper.cpp engine: argv shape and the JSON-to-Transcript translation.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local engine = require("media.engines.whisper_cpp")

  H.eq(engine.id, "whisper_cpp", "the id the registry keys on")

  -- ── argv ──────────────────────────────────────────────────────────────
  local argv = engine.args({
    bin = "whisper-cli",
    wav_path = "/tmp/talk.wav",
    model = "/models/ggml-base.en.bin",
    out_prefix = "/tmp/talk",
    lang = "en",
  })
  H.before(argv, "-f", "-oj", "the input precedes the output flags")
  local m = H.index_of(argv, "-m")
  H.eq(argv[m + 1], "/models/ggml-base.en.bin", "the model path reaches the binary")
  local of = H.index_of(argv, "-of")
  H.eq(argv[of + 1], "/tmp/talk", "the output prefix has no extension of its own")
  local l = H.index_of(argv, "-l")
  H.eq(argv[l + 1], "en", "the forced language reaches whisper.cpp")
  H.falsy(H.index_of(argv, "-tr"), "no translate flag when the task is plain transcription")

  -- ── an unset language omits -l entirely ──────────────────────────────
  local auto = engine.args({
    bin = "whisper-cli",
    wav_path = "/tmp/talk.wav",
    model = "/models/ggml-base.en.bin",
    out_prefix = "/tmp/talk",
  })
  H.falsy(H.index_of(auto, "-l"), "no language flag means whisper.cpp detects it")

  -- ── translate ─────────────────────────────────────────────────────────
  local translated = engine.args({
    bin = "whisper-cli",
    wav_path = "/tmp/talk.wav",
    model = "/models/ggml-base.en.bin",
    out_prefix = "/tmp/talk",
    translate = true,
  })
  H.ok(H.index_of(translated, "-tr"), "task = translate reaches whisper.cpp's own flag")

  -- ── JSON → Media.Transcript ───────────────────────────────────────────
  local doc = {
    result = { language = "en" },
    transcription = {
      { offsets = { from = 0, to = 2000 }, text = " Hello there." },
      { offsets = { from = 2000, to = 4500 }, text = " General Kenobi." },
    },
  }
  local transcript = engine.from_json(doc, "/models/ggml-base.en.bin")
  H.eq(transcript.engine, "whisper_cpp", "the transcript records which engine made it")
  H.eq(transcript.lang, "en", "the detected language comes through")
  H.eq(#transcript.segments, 2, "one segment per transcription entry")
  H.eq(transcript.segments[1].s, 0, "offsets convert from ms to seconds")
  H.eq(transcript.segments[2].e, 4.5, "the second segment's end, in seconds")
  H.eq(transcript.segments[1].text, "Hello there.", "leading/trailing space trimmed")
  H.eq(transcript.text, "Hello there. General Kenobi.", "the flat text is every segment joined")

  -- ── a transcription entry with no offsets does not error ─────────────
  local sparse = engine.from_json({ transcription = { { text = "just this" } } }, nil)
  H.eq(sparse.segments[1].s, 0, "a missing offset falls back to zero rather than throwing")
  H.eq(sparse.model, nil, "no model recorded when none was given")
end
