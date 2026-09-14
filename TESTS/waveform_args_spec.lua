-- The waveform/spectrogram filter chain.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local waveform = require("media.core.waveform")

  local wave = waveform.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/song.mp3",
    out = "/tmp/waveform.png",
    width = 1200,
    height = 300,
    mode = "wave",
    colors = "#9cdcfe",
  })

  local fc = H.index_of(wave, "-filter_complex")
  H.ok(fc, "there is a filter graph")
  local wave_filter = wave[fc + 1]
  H.match(wave_filter, "^showwavespic=s=1200x300", "size comes first")
  H.match(wave_filter, "colors=#9cdcfe", "the configured colour reaches ffmpeg")
  H.eq(wave[#wave], "/tmp/waveform.png", "the output path is last")
  H.before(wave, "-i", "-filter_complex", "the input precedes the graph that reads it")

  -- ── An unset colour still reaches ffmpeg, not left to its own default ────
  -- White draws invisibly against a light terminal background.
  local uncoloured = waveform.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/song.mp3",
    out = "/tmp/waveform.png",
    width = 640,
    height = 120,
    mode = "wave",
  })
  local uc_filter = uncoloured[H.index_of(uncoloured, "-filter_complex") + 1]
  H.match(uc_filter, "colors=white", "white is the explicit fallback, not ffmpeg's implicit one")

  -- ── The spectrogram takes no `colors` argument ───────────────────────────
  local spectrum = waveform.args({
    ffmpeg = "ffmpeg",
    path = "/tmp/song.mp3",
    out = "/tmp/spectrogram.png",
    width = 1200,
    height = 300,
    mode = "spectrum",
  })
  local sp_filter = spectrum[H.index_of(spectrum, "-filter_complex") + 1]
  H.match(sp_filter, "^showspectrumpic=s=1200x300$", "no colours knob on this filter")
end
