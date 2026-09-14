-- The WAV-extraction filter chain.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local normalize = require("media.core.normalize")

  local argv = normalize.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/voicemail.m4a",
    out = "/tmp/voicemail.wav",
  })

  H.before(argv, "-i", "-ar", "the input precedes the filters that read it")
  local ac = H.index_of(argv, "-ac")
  H.ok(ac, "channels are forced")
  H.eq(argv[ac + 1], "1", "mono — what whisper.cpp's models were trained on")
  local ar = H.index_of(argv, "-ar")
  H.eq(argv[ar + 1], "16000", "16 kHz — the other half of that requirement")
  H.ok(H.index_of(argv, "-vn"), "no picture in a WAV")
  H.eq(argv[#argv], "/tmp/voicemail.wav", "the output path is last")
end
