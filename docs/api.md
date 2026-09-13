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
media.play(path)                                                     -- hand off to the configured / system player

media.frames(path, { count = 24, fps = 12 }, function(pngs, err) end)  -- a run, for block-graphics playback
media.audio(path, { at = 0 }, function(handle, err) end)              -- sound for that run — see media.audio_available()

local handle = media.play_window(path, { at = 90 })                  -- a real mpv window; see media.player_available()
-- handle.stop()  -- ends the window and its process tree; idempotent, and run for you at :qa
```

Every callback runs exactly once and on the main loop, so it may touch the
Neovim API. A cache hit still calls back asynchronously — a function that is
sometimes synchronous is the harder contract to write against.

`require("media.ui").summary(probe)` returns the one-line form
(`1920x1080 · 4:32 · h264 · 100 MB`) so two consumers do not invent two
different words for the same file.
