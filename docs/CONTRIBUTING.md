# Contributing

## Layout

```
lua/media/
  init.lua              -- the public API; every other module is an implementation detail
  formats.lua           -- which extensions are claimed
  ui.lua                -- windows and strings; nothing another plugin consumes
  health.lua            -- :checkhealth media
  config/
    DEFAULTS.lua        -- every default, with the reasoning next to it
    init.lua            -- merge and hand out
  core/
    bin.lua             -- finding ffmpeg, ffprobe, mpv, whisper-cli
    probe.lua           -- ffprobe JSON -> one flat record
    frame.lua           -- one still
    frames.lua          -- a run of stills at a fixed rate -- the decode half of playback
    sheet.lua           -- a grid of stills
    waveform.lua        -- a waveform or spectrogram picture of the audio track
    audio.lua           -- an audio-only mpv, talked to over its JSON IPC
    player.lua          -- a real mpv window, opened on a file and owned by its caller
    cache.lua           -- the on-disk store and the request coalescing
    play.lua            -- the handoff to a real player
    proc.lua            -- stopping a spawned process -- which on Windows is not `kill`
    normalize.lua       -- any file with sound, reduced to 16 kHz mono WAV
    registry.lua        -- transcription engine registry
    resolver.lua        -- engine selection and fallback-chain resolution
    segments.lua        -- the timestamped transcript model, shared by every engine
    dispatcher.lua      -- probe -> normalize -> transcribe -> cache, behind one cancellable call
  engines/
    init.lua            -- loads and registers every built-in transcription engine
    whisper_cpp.lua     -- local transcription via whisper.cpp's `whisper-cli`
  output/
    init.lua            -- delivering a finished transcript: buffer | sidecar | srt | vtt
    sidecar.lua         -- `<file>.transcript.md`
    srt.lua             -- SubRip; the comma in its timestamp is the classic trap
    vtt.lua             -- WebVTT; cue text is markup, unlike SubRip's
  hub/
    kinds.lua           -- image | pdf | audio | video | other, and the sidecar each would write
    scan.lua            -- cfile/cwd/path=<dir>, the walk, and missing | stale | ok | none
    text.lua            -- `:Media text` -- one verb, four kinds, every route a pcall
    dashboard.lua       -- the row format, the float, the keys and the batch
    actions.lua         -- what you can do to a row, and doing it to several at once
  integrations/
    menu.lua            -- the same actions on the right mouse button
  bindings/
    init.lua            -- one entry point, idempotent
    keymaps.lua         -- the four keys
    usrcmds.lua         -- :Media and its routes
    autocmds.lua        -- one, and a note about the one that is missing on purpose
  @types/init.lua       -- every alias, defined once
```

`core/` is the half other plugins consume. `ui.lua` and `bindings/` are the half
that exists so a person can use it directly — nothing in `core/` may require
either.

## Tests

```bash
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
     -c "luafile TESTS/run.lua" -c "qa!"
```

Framework-free, and needs **no ffmpeg**. That is not a limitation but the design:
the decisions worth asserting — argument order, offset arithmetic, cache-key
separation, ffprobe's JSON shapes — are all pure functions, split out from the
processes that use them for exactly this reason.

The runner exits non-zero on any failure and prints which spec failed. If you add
a spec, add its filename to the list in `TESTS/run.lua`; `smoke_spec.lua` stays
last, because it calls `setup()` and the specs before it assert against a state
where that has not happened.

## Ground rules

- **A new external binary needs a reason no existing one covers.** ImageMagick,
  GStreamer and mpv can all produce a still; none can produce one ffmpeg cannot.
- **A pure function over a process wherever the decision is in the arguments.**
  `frame.args`, `sheet.args`, `probe.from_ffprobe`, `cache.key` and `ui.describe`
  are public for testability, not because a consumer needs them.
- **Every callback runs exactly once, and on the main loop.** A cache hit still
  goes through `vim.schedule` — a function that is sometimes synchronous is the
  harder contract to write against.
- **Optional dependencies degrade, they do not error.** lib.nvim missing costs
  tab completion; images.nvim missing costs an in-terminal draw. Neither costs
  the feature.
- **Comment what is not visible in the code.** Why `-ss` precedes `-i`, why cover
  art is not seeked, why the sheet has its own timeout. Not what the line does.

Run `stylua .` and `luacheck lua plugin TESTS` before opening a pull request —
CI gates on both, pinned to the versions in `.github/workflows/ci.yml`.
