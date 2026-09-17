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

  -- ── the real document, observed 2026-09-17 ───────────────────────────
  -- The fixture above was transcribed from whisper.cpp's source and had never
  -- been checked against a run. This is the actual `-oj` output of a real
  -- build on `samples/jfk.wav` — kept so a future whisper.cpp that changes the
  -- shape fails here rather than in a scratch window that comes up empty.
  local observed = engine.from_json({
    systeminfo = "WHISPER : VITISAI = 0 | COREML = 0 | …",
    model = { type = "base", multilingual = false },
    params = { model = "C:\\tools\\whisper.cpp\\ggml-base.en.bin", language = "en" },
    result = { language = "en" },
    transcription = {
      {
        timestamps = { from = "00:00:00,000", to = "00:00:11,000" },
        offsets = { from = 0, to = 11000 },
        text = " And so my fellow Americans, ask not what your country can do for you.",
      },
    },
  }, "/models/ggml-base.en.bin")
  H.eq(#observed.segments, 1, "the observed document parses")
  H.eq(observed.segments[1].s, 0, "")
  H.eq(observed.segments[1].e, 11, "offsets really are milliseconds — 11000 is eleven seconds")
  H.eq(observed.lang, "en", "")
  H.match(observed.text, "^And so my fellow Americans", "")
  H.eq(
    observed.duration,
    nil,
    "no duration: whisper.cpp's JSON carries none, and the last segment's end is the transcribed extent rather than the file's"
  )

  -- ── the reason out of stderr ─────────────────────────────────────────
  -- `whisper-cli` exits 0 on some failures (measured: a file it cannot decode
  -- gives code 0 and no JSON), so the reason comes from stderr or not at all.
  -- These are the real lines from that run.
  H.eq(
    engine.failure_reason(
      "read_audio_data: reading audio data from 'x.wav' ...\n"
        .. "read_audio_data: trying to decode with miniaudio\n"
        .. "read_audio_data: failed to read audio data\n"
        .. "error: failed to read audio file 'x.wav'\n"
    ),
    "failed to read audio file 'x.wav'",
    "the `error:` line is picked out from among the progress lines `-np` leaves behind"
  )
  H.eq(
    engine.failure_reason("error: failed to initialize whisper context"),
    "failed to initialize whisper context",
    "and the one a missing model produces"
  )
  H.eq(
    engine.failure_reason("read_audio_data: reading audio data from 'x.wav' ...\n"),
    nil,
    "progress lines alone are not a failure"
  )
  H.eq(engine.failure_reason(nil), nil, "")
  H.eq(engine.failure_reason(""), nil, "")
end
