# Configuration

Nothing here has to be set. `setup()` is optional, and every default is chosen
to be useful on its own.

```lua
require("media").setup({
  bin = { ffmpeg = nil, ffprobe = nil },
  timeout_ms = 15000,
  frame = { at = "10%", width = 800 },
  sheet = { rows = 3, cols = 4, width = 1200, margin = 4, timeout_ms = 120000 },
  cache = { enabled = true, dir = nil },
  player = nil,
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

An explicit path, for the case where the binary is installed but not on PATH.
The plugin probes winget's and scoop's shim directories, chocolatey's `bin`,
`C:/ffmpeg/bin`, `/opt/homebrew/bin` and `/usr/local/bin` by itself — this is the
escape hatch for everything it does not guess.

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
