# Configuration

Nothing here has to be set. `setup()` is optional, and every default is chosen
to be useful on its own.

```lua
require("media").setup({
  bin = { ffmpeg = nil, ffprobe = nil, mpv = nil, ["whisper-cli"] = nil },
  timeout_ms = 15000,
  frame = { at = "10%", width = 800 },
  sheet = { rows = 3, cols = 4, width = 1200, margin = 4, timeout_ms = 120000 },
  waveform = { width = 1200, height = 300, colors = "#9cdcfe", timeout_ms = 120000 },
  transcribe = {
    engine = "whisper_cpp",
    fallback = {},
    lang = nil,
    task = "transcribe",
    output = "buffer",
    cache = true,
    timeout_ms = 0,
    normalize_timeout_ms = 120000,
    whisper_cpp = { model = nil },
  },
  cache = { enabled = true, dir = nil },
  player = nil,
  window = { autofit = "80%x80%", ontop = true, args = {} },
  keymaps = {
    preset = true,
    probe = "<leader>Mp",
    frame = "<leader>Mf",
    sheet = "<leader>Ms",
    play  = "<leader>Mo",
    which_key = true,
  },
})
```

The full reasoning for each default is in
[`lua/media/config/DEFAULTS.lua`](../lua/media/config/DEFAULTS.lua); this page is
the summary.

## `bin`

| Key | Type | Default |
| --- | --- | --- |
| `bin.ffmpeg` | `string\|nil` | `nil` |
| `bin.ffprobe` | `string\|nil` | `nil` |
| `bin.mpv` | `string\|nil` | `nil` |
| `bin["whisper-cli"]` | `string\|nil` | `nil` |

An explicit path, for the case where the binary is installed but not on PATH.
The plugin probes winget's and scoop's shim directories, chocolatey's `bin`,
`C:/ffmpeg/bin`, `/opt/homebrew/bin` and `/usr/local/bin` by itself — this is the
escape hatch for everything it does not guess. `mpv` is looked up the same way
as `ffmpeg`/`ffprobe` and is optional: it is only used for `media.audio`, and
its absence just means a played run stays silent.

An explicit path is honoured even when it does not exist, on purpose: the error
you then get names your own setting, which is a better place to start looking
than "ffmpeg not found".

## `timeout_ms`

| Type | Default |
| --- | --- |
| `integer` | `15000` |

Hard ceiling on any one `ffprobe` or poster-frame run. It exists because of a
specific failure rather than as a formality: ffmpeg reading a file over a stalled
network mount, or a truncated download with no moov atom, does not fail — it
waits.

## `frame`

| Key | Type | Default |
| --- | --- | --- |
| `frame.at` | `number\|string` | `"10%"` |
| `frame.width` | `integer` | `800` |

`at` is seconds when it is a number, a fraction of the duration when it ends in
`%`, and handed to ffmpeg untouched otherwise — so `"00:01:23.5"` works.

Ten percent rather than zero because of what the first frame of a real video
usually is: black, a fade-in, a distributor's logo, or a slate.

`width` is chosen against the consumer, not the source: a hover float is at most
a few hundred cells wide, and every pixel past what the terminal will draw is
decode time and cache bytes spent on nothing.

## `frames`

A run of stills at a fixed rate — the decode half of block-graphics playback.
Nothing here draws them: `media.frames(path, opts, cb)` hands back PNG paths
in order, plus a handle whose `cancel()` kills the decode and guarantees the
callback never fires.

| Key | Default | What it does |
| --- | --- | --- |
| `from` | `nil` | Where a run starts. Seconds, `"10%"`, or an ffmpeg timestamp; `nil` is the beginning |
| `fps` | `12` | Stills per second of source material — the sampling rate, not the playback rate. The low end of what reads as motion, and half the decode and cache of 24 |
| `count` | `24` | Stills per run. Two seconds at 12 fps: short enough to arrive quickly, long enough that the next run can be decoded while it plays |
| `width` | `320` | Pixel width before a consumer samples it into cells. Much smaller than `frame.width`, and that difference is paid `count` times |

A run that reaches the end of the file returns however many stills exist —
partial output is a result, not a failure, or the end of every video would be
unplayable.

## `sheet`

| Key | Type | Default |
| --- | --- | --- |
| `sheet.rows` | `integer` | `3` |
| `sheet.cols` | `integer` | `4` |
| `sheet.width` | `integer` | `1200` — the finished sheet, not one tile |
| `sheet.margin` | `integer` | `4` |
| `sheet.timeout_ms` | `integer` | `120000` |

The sheet has its own timeout because it is a categorically different operation:
a poster frame is a seek, a sheet is a pass over the whole file. Files longer
than two minutes are decoded from keyframes only, which makes that pass seconds
rather than minutes and costs nothing at that length.

## `waveform`

| Key | Type | Default |
| --- | --- | --- |
| `waveform.width` | `integer` | `1200` |
| `waveform.height` | `integer` | `300` |
| `waveform.colors` | `string` | `"#9cdcfe"` |
| `waveform.timeout_ms` | `integer` | `120000` |

Backs both `media.waveform()`/`:Media waveform` and
`media.spectrogram()`/`:Media spectrogram` — `showwavespic` and
`showspectrumpic` differ only in which picture ffmpeg draws, not in how the
process is run or cached. `colors` is `showwavespic`'s own argument and is
ignored for a spectrogram; it is always passed explicitly because ffmpeg's own
default (white) draws invisibly against a light terminal background.

Same reasoning as `sheet.timeout_ms` for the ceiling: both filters read every
sample of the file once rather than seek, so this is not the interactive
`timeout_ms`.

## `render_concurrency`

| Key | Type | Default |
| --- | --- | --- |
| `render_concurrency` | `integer` | `4` |

How many `ffmpeg` renders may run at once.

**A bound on a storm, not a throughput setting.** Raising it does not make a
directory of thumbnails appear sooner — each render is already a multi-threaded
decode, and four of them on four cores is where they start taking the work off
each other. What it prevents is the other end. Measured 2026-09-17, before this
existed:

| | concurrent `ffmpeg` processes |
| --- | --- |
| holding a paging key down in a video hover (30 presses) | 30 |
| the same, with prefetching behind each press | 60 |
| with a playback window on top | 61 |

All three are 4 now, and nothing is dropped — the queue delays, it does not
discard.

**A playback window jumps the queue regardless of this number**, because it is
the one render with a deadline: `hover.nvim`'s transport asks for the next
window a second before it needs it. Queued behind thirty stills it arrived at
**1111 ms**; ahead of them, at **243 ms**. That measurement is why the queue has
priorities at all rather than being a plain FIFO.

A prefetch goes last, and one that never runs because the queue stayed busy has
lost nothing — the real request behind it does the work.

## `hub`

What the dashboard's scan walks into, and how far it goes before giving up.

| Key | Type | Default |
| --- | --- | --- |
| `hub.exclude` | `string[]` | `{ ".venv", "target", "dist", "build", ".cache" }` |
| `hub.max_entries` | `integer` | `20000` |

`.git` and `node_modules` are **always** skipped and are not in this list.
They are separate because they are not a preference: `node_modules` is where an
entry cap goes to die, and a scan that descended into it would find nothing but
dependencies.

`max_entries` is a safety net against a `cwd` that turns out to be a home
directory, not a limit anyone should reach on purpose. Hitting it is a **quiet
stop**, not an error — what was found before it is still the right answer to
show, and a dashboard refusing to draw because a directory was large would be
the worse failure. Same number and same reasoning as `images.browse`'s own cap.

## `progress_style`

| Key | Type | Default |
| --- | --- | --- |
| `progress_style` | `"auto"\|"notify"\|"statusline"\|"fidget"\|"float"\|"kit"` | `"auto"` |

How `:Media transcribe` shows that it is working. The names are
`lib.nvim.progress`'s own and are passed straight through; `"auto"` picks
whatever is installed.

**`"float"` is the one with a cancel key.** Focus the window and press `<Esc>`
in normal mode and the run stops — the whole pipeline, ffmpeg included, not
just the callback. The other styles report and nothing more, which for a
process that can run for minutes is worth knowing before picking one.

Without lib.nvim installed there is no indicator and the command says
"transcribing…" once, as it always did. Nothing fails over a missing one, and
`:checkhealth media` reports which of the two cases you are in.

## `transcribe`

| Key | Type | Default |
| --- | --- | --- |
| `transcribe.engine` | `string` | `"whisper_cpp"` |
| `transcribe.fallback` | `string[]` | `{}` |
| `transcribe.lang` | `string\|nil` | `nil` — let the engine detect it |
| `transcribe.task` | `"transcribe"\|"translate"` | `"transcribe"` |
| `transcribe.output` | `"buffer"\|"sidecar"\|"srt"\|"vtt"` | `"buffer"` |
| `transcribe.cache` | `boolean` | `true` |
| `transcribe.timeout_ms` | `integer` | `0` — no timeout |
| `transcribe.normalize_timeout_ms` | `integer` | `120000` |
| `transcribe.whisper_cpp.model` | `string\|nil` | `nil` |

One engine so far (ROADMAP.md's "Transcription" section), with `fallback`
empty because there is nothing yet to fall back to.

`output` picks where a finished transcript goes: `"buffer"` a scratch
window, `"sidecar"` a `<file>.transcript.md`, and `"srt"`/`"vtt"` subtitle
files written beside the source as `<file>.srt`/`<file>.vtt`. The default
stays the buffer because a machine transcript is worth reading before it is
worth keeping; `:Media transcribe out=` overrides it per call.

`timeout_ms` defaults to **no timeout**, deliberately — the interactive
`timeout_ms` at the top of this file (15 s) would kill every real
transcription; an hour of audio is minutes of work, not seconds.
`normalize_timeout_ms` is separate and does have a default ceiling, for the
WAV-extraction step that runs first: same reasoning as `sheet.timeout_ms`,
a full read of the file rather than a seek.

`whisper_cpp.model` is never set automatically and never downloaded — it has
to be an absolute path to a GGML `.bin` file you already have.
`:checkhealth media` reports whether `whisper-cli` is on PATH and whether
this points at a file that exists, but never fetches one.

`"translate"` asks whisper.cpp for its own translate task, which only ever
produces **English**. Every other target language is
[language.nvim](https://github.com/StefanBartl/language.nvim)'s job,
downstream of this plugin, not a `task` value here.

## `cache`

| Key | Type | Default |
| --- | --- | --- |
| `cache.enabled` | `boolean` | `true` |
| `cache.dir` | `string\|nil` | `nil` → `stdpath("cache")/media.nvim` |

Rendered stills live on disk and outlive the session. The key carries the source
file's mtime, so an entry is safe to keep forever and an edited file misses.
`:Media cache clear` empties it.

## `player`

| Type | Default |
| --- | --- |
| `string\|string[]\|nil` | `nil` |

What `:Media play` launches. `nil` hands the file to the system's default
handler — the choice you already made once, in your desktop environment. A
string or argv list overrides it:

```lua
player = { "mpv", "--loop-file=no" }
```

> On Windows the player's window opens *behind* the terminal. Windows grants
> `SetForegroundWindow` only to the process owning the foreground window, and
> inside a terminal that is the terminal host, not `nvim.exe`. Under a GUI
> Neovim the same call puts it in front, which makes this look intermittent
> rather than structural.

## `window`

| Key | Type | Default |
| --- | --- | --- |
| `window.autofit` | `string` | `"80%x80%"` |
| `window.ontop` | `boolean` | `true` |
| `window.args` | `string[]` | `{}` |

The windowed mpv player behind `media.play_window()` and `:Media window` — the
one a consumer opens on a video and stops again by a handle (`hover.nvim` uses
it for the `<CR>` in a video hover). Always mpv, unlike `player`, because a
controllable window needs the same binary every time.

- **`autofit`** is mpv's `--autofit-larger`: the window shrinks to fit inside
  this fraction of the screen and never grows a small video past its own pixels.
  `""` leaves the size to mpv.
- **`ontop`** keeps the window above the terminal whatever has focus. On by
  default because the caller opening it generally cannot bring it to the front
  (the `player` note above), and a player you cannot see is not a player. Tied
  to a hover, the window is short-lived anyway.
- **`args`** is appended verbatim just before the file: `--loop`, `--speed=1.5`,
  a `--profile`, an `--sub-file` — anything mpv takes.

`screen` is not a `window` config key — it is a per-call `play_window` option,
because it names *where the caller currently is*, not a standing preference.
It picks which display `autofit`'s and `--geometry`'s percentages resolve
against; without it both key off whatever mpv treats as screen 0. Added for
`hover.nvim`'s `<CR>`, which asks its own terminal window's monitor first.

```lua
window = { autofit = "60%x60%", ontop = false, args = { "--loop" } }
```

```lua
local handle = require("media").play_window(path, { at = 90, mute = true, screen = 1 })
if not handle then return end -- no mpv — never an error
handle.stop()                  -- ends the window and its process tree; idempotent
```

`handle.stop()` runs for you at `:qa` even if the caller never calls it — an
mpv window is a real OS process and would otherwise outlive the editor, the same
failure `media.audio` guards against.

## `audio`

Not a `setup()` table — `media.audio(path, { at = 0 }, callback)` is called
directly, the same way `media.frame`/`media.frames` are. It starts `bin.mpv`
audio-only (`--no-video`) on `path` and hands the callback a handle once
mpv's own JSON IPC socket answers:

```lua
media.audio(path, { at = 12.5 }, function(handle, err)
  if not handle then return end -- no mpv, or its socket never came up — never an error
  handle.pause()
  handle.resume()
  handle.seek(30)
  handle.time_pos(function(seconds) end)
  handle.stop()
end)
```

Built for `hover.nvim`'s played run, which needs a clock more accurate than a
Lua timer: the picture is drawn against whatever `time_pos` answers, not
against a frame count, so it cannot drift from the sound the way two
independently free-running timers would. See `lua/media/core/audio.lua`'s
module header for the full reasoning, including why this had to be a real
player (`ffplay` never reports its position) and not a decoder.

## `keymaps`

| Key | Type | Default |
| --- | --- | --- |
| `keymaps.preset` | `boolean` | `true` — `false` binds nothing |
| `keymaps.probe` | `string\|string[]\|false` | `<leader>Mp` |
| `keymaps.frame` | `string\|string[]\|false` | `<leader>Mf` |
| `keymaps.sheet` | `string\|string[]\|false` | `<leader>Ms` |
| `keymaps.play` | `string\|string[]\|false` | `<leader>Mo` |
| `keymaps.which_key` | `table\|boolean` | `true` |

`<leader>M` was picked because the capital-M leader space is conventionally
unused, and because these four want to sit together under one which-key group
rather than compete for single letters.
