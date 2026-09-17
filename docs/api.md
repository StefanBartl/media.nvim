# Lua API

The point of this plugin is to be consumed. The whole surface:

```lua
local ok, media = pcall(require, "media")
if not ok or not media.available() then
  return -- degrade; do not error
end

media.is_video(path)                    -- by extension, no process started
media.probed(path)                      -- what is already known, synchronous, may be nil

media.probe(path, function(probe, err)
  -- probe.duration, .width, .height, .fps, .video_codec, .has_audio, …
end)

media.frame(path, { at = "10%", width = 800 }, function(png, err)
  -- png is a path to a PNG on disk; hand it to whatever draws pictures
end)

media.sheet(path, { rows = 3, cols = 4 }, function(png, err) end)
media.waveform(path, {}, function(png, err) end)                     -- sound equivalent of a poster frame
media.spectrogram(path, {}, function(png, err) end)                  -- same shape, frequency content instead
media.play(path)                                                     -- hand off to the configured / system player

media.frames(path, { count = 24, fps = 12 }, function(pngs, err) end)  -- a run, for block-graphics playback
media.audio(path, { at = 0 }, function(handle, err) end)              -- sound for that run — see media.audio_available()

media.transcribe(path, {}, function(transcript, err)                  -- speech to text; see media.transcribe_available()
  -- transcript.text, transcript.segments = { { s, e, text }, … }
end)

local handle = media.play_window(path, { at = 90 })                  -- a real mpv window; see media.player_available()
-- handle.stop()  -- ends the window and its process tree; idempotent, and run for you at :qa
```

Every callback runs exactly once and on the main loop, so it may touch the
Neovim API. A cache hit still calls back asynchronously — a function that is
sometimes synchronous is the harder contract to write against.

`require("media.ui").summary(probe)` returns the one-line form
(`1920x1080 · 4:32 · h264 · 100 MB`) so two consumers do not invent two
different words for the same file.

`media.transcribe` hands back the `Media.Transcript` and nothing else — it
does not write a buffer, a sidecar or a subtitle file itself, the same
division `media.frame` draws with `media.ui.show_image`. `:Media transcribe`
(and its `out=` argument) is the thing that calls
`require("media.output").deliver(path, transcript, mode)`; a consumer wanting
the same delivery calls it directly.

```lua
local output = require("media.output")

output.MODES                            -- { "buffer", "sidecar", "srt", "vtt" }
output.is_mode("srt")                   -- true; check this BEFORE a run, not after
output.written_path(path, "srt")        -- "<path>.srt", or nil for a buffer
output.deliver(path, transcript, "srt") -- ok, err
```

### Serialising without delivering

Both subtitle formats are pure functions on a transcript, so anything that
wants the document rather than the file takes it straight:

```lua
local srt = require("media.output.srt").serialize(transcript)  -- SubRip
local vtt = require("media.output.vtt").serialize(transcript)  -- WebVTT
```

Nothing there touches disk, ffmpeg or an engine. The shared preparation —
dropping empty segments, repairing a zero-length one without discarding its
text, and collapsing a blank line that would otherwise end the cue — is
`require("media.core.segments").cues(segments)`, and both serialisers read it
so the two formats cannot disagree about what a transcript says.
