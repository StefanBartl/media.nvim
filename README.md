> **Beta stage — active development.** This repository is past its first shape and in
> active use, but the surface is not frozen: breaking changes are still possible. Pin a
> commit or tag if you depend on it.

# media.nvim

```
███╗   ███╗███████╗██████╗ ██╗ █████╗
████╗ ████║██╔════╝██╔══██╗██║██╔══██╗
██╔████╔██║█████╗  ██║  ██║██║███████║
██║╚██╔╝██║██╔══╝  ██║  ██║██║██╔══██║
██║ ╚═╝ ██║███████╗██████╔╝██║██║  ██║
╚═╝     ╚═╝╚══════╝╚═════╝ ╚═╝╚═╝  ╚═╝
                                 .nvim
```

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Neovim](https://img.shields.io/badge/Neovim-0.10%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io)
[![Lua](https://img.shields.io/badge/Lua-5.1%2FLuaJIT-2C2D72?logo=lua&logoColor=white)](https://www.lua.org)
![Status](https://img.shields.io/badge/status-beta-orange)
![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-lightgrey)
[![CI](https://github.com/StefanBartl/media.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/StefanBartl/media.nvim/actions/workflows/ci.yml)

**What is in this media file, and one picture of it.** `ffprobe` says how long,
how big and in which codec; `ffmpeg` produces a poster frame or a contact sheet
as a PNG on disk. Anything that can draw a picture can then show a video.

Neovim's ecosystem can draw an image and can read a PDF, and both of those are
somebody's plugin already. Nothing turned a video into either — so a `.mp4`
under the cursor was, everywhere, a size in bytes and the word "binary".

---

## Table of contents

- [Documentation](#documentation)
- [What it does](#what-it-does)
- [What it does not do](#what-it-does-not-do)
- [Around it](#around-it)
- [Requirements](#requirements)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [What you get](#what-you-get)
- [For plugin authors](#for-plugin-authors)
- [Health check](#health-check)
- [Contributing](#contributing)
- [Feedback](#feedback)
- [License](#license)

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

- [Installation](docs/installation.md) — requirements, plugin managers, load triggers.
- [Configuration](docs/configuration.md) — every `setup()` option and its default.
- [Command reference](docs/commands.md) — every command and argument.
- [Bindings cheatsheet](docs/BINDINGS.md) — keymaps, commands and autocommands at a glance.
- [Health check](docs/health.md) — what `:checkhealth media` reports, line by line.

`:help media` is the same reference inside the editor.

---

## What it does

Three answers, and nothing else.

| | |
| --- | --- |
| **Describe** | `ffprobe` in one process, flattened into one record: duration, size, bitrate, resolution, frame rate, codecs, channels. |
| **Poster frame** | One still, seeked to a configurable offset, scaled and cached as a PNG. |
| **Contact sheet** | The whole running time as a grid of stills — one render, one picture, no playback. |
| **Frame run** | A stretch of the file as a numbered sequence of stills, one ffmpeg pass, cancellable — what a consumer that can draw cells turns into moving picture. |

Three details are the reason this is a plugin rather than a `vim.system` call in
your config:

**Rotation is applied.** A video recorded on a phone held upright stores
1920x1080 frames plus a 90-degree display matrix, and is 1080x1920 on screen.
`media.probe` reports the display pair, so a consumer sizing a window from it
draws a portrait box around a portrait picture.

**Cover art is not a video.** An mp3 with album art has a video stream, and
ffprobe says so truthfully. Taking that at face value makes every tagged music
file look like a one-frame film — and seeking into it writes no file at all.
`has_video` and `has_cover` are separate answers here.

**The seek goes before the input.** `-ss` as an *input* option jumps to the
nearest keyframe; after `-i` it decodes the file from the beginning and throws
everything away up to the offset. Same picture. On a two-hour file, a fifth of a
second against half a minute.

Rendered stills are cached on disk under a key that carries the source file's
mtime, so an entry is safe to keep forever and an edited file misses.

---

## What it does not do

**It does not paint anything, and it does not play anything.** It produces PNGs
and it drives a player; what happens to either is a consumer's business. That
line is where it stays, for the same reason images.nvim keeps to its own side of
it.

**Nothing in a terminal Neovim can show a video as a real picture**, which is
worth stating precisely because it decides the shape of everything above. The
only image protocol that reaches the terminal from inside Neovim carries a whole
base64 payload per write and has no notion of a frame, and Neovim repaints over
anything drawn between its own redraws. The Kitty protocol has animation frames
and would be the right tool — measured 2026-08-05, on Windows in WezTerm nothing
sent from inside Neovim renders through it at all.

What does move the line is a consumer that draws *text*.
[hover.nvim](https://github.com/StefanBartl/hover.nvim) asks for a run of stills
through `media.frames()` and paints them as coloured blocks — which collide with
no graphics protocol and survive every redraw — with sound from the mpv this
plugin drives over its JSON IPC socket. `:Media play` remains the other honest
answer: hand the file to a real player.

---

## Around it

> **[images.nvim](https://github.com/StefanBartl/images.nvim)** — draws the PNGs
> this produces, in the terminal, over OSC 1337. It reads no media formats and
> does not want to; this plugin is the other half of that division.
>
> **[pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim)** — the same
> shape for PDFs: an external toolchain wrapped once, exposed as verbs, consumed
> by anything that wants them. It was the structural template for this
> repository.
>
> **[hover.nvim](https://github.com/StefanBartl/hover.nvim)** — the first
> consumer: a `.mp4` path under the cursor opens a float with the poster frame
> in it, in the video's own aspect ratio.
>
> All of the above are soft: without them everything else works unchanged.
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) is the one real
> dependency — see [Requirements](#requirements).

---

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required — keymap registry, `:Media` completion, cross-platform open |
| `ffmpeg` | required — the renderer |
| `ffprobe` | required — ships with ffmpeg |

```bash
winget install Gyan.FFmpeg
```

macOS: `brew install ffmpeg`. Debian/Ubuntu: `sudo apt install ffmpeg`.

> On Windows, restart the terminal after installing: winget and scoop extend the
> *user* PATH, which every already-running process inherited at login. This
> plugin probes both shim directories anyway, so it usually finds ffmpeg before
> you notice — see `core/bin.lua`.

Optional, each detected at runtime and degrading to nothing when absent:

| | |
| --- | --- |
| [images.nvim](https://github.com/StefanBartl/images.nvim) | rendered stills are shown in the terminal instead of an external viewer |
| `mpv` (or any player) | `:Media play` uses it instead of the system's default handler |

---

## Installation

```lua
-- lazy.nvim
{
  "StefanBartl/media.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

`VeryLazy` rather than `cmd = { "Media" }` because the four keymaps have to
exist before you press one. If you only ever use the command, `cmd` is the
cheaper trigger — the plugin file itself registers nothing at startup.

Other plugin managers and the load-trigger variants are in
[docs/installation.md](docs/installation.md).

---

## Quickstart

Put the cursor on a path to a video — in a file tree, in a markdown link, in a
directory listing — and press `<leader>Mp`. Or name it:

```vim
:Media probe ~/Videos/holiday.mp4
```

Then the picture:

```vim
:Media frame                  " poster frame of the file under the cursor
:Media frame at=50% width=1200
:Media sheet rows=4 cols=5    " the whole file as a grid
```

Verify your setup any time with:

```vim
:checkhealth media
```

---

## What you get

| Key / command | Where | Does |
| --- | --- | --- |
| `<leader>Mp` | normal | describe the file under the cursor |
| `<leader>Mf` | normal | poster frame |
| `<leader>Ms` | normal | contact sheet |
| `<leader>Mo` | normal | play in an external player |
| `:Media [path]` | command | the same description, by name |
| `:Media cache clear` | command | throw the rendered stills away |

The full set is the [bindings cheatsheet](docs/BINDINGS.md).

---

## For plugin authors

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
media.play(path)

media.frames(path, { count = 24, fps = 12 }, function(pngs, err) end)  -- a run, for block-graphics playback
media.audio(path, { at = 0 }, function(handle, err) end)              -- sound for that run — see media.audio_available()
```

Every callback runs exactly once and on the main loop, so it may touch the
Neovim API. A cache hit still calls back asynchronously — a function that is
sometimes synchronous is the harder contract to write against.

`require("media.ui").summary(probe)` returns the one-line form
(`1920x1080 · 4:32 · h264 · 100 MB`) so two consumers do not invent two
different words for the same file.

---

## Health check

```vim
:checkhealth media
```

Verifies both binaries, reports ffmpeg's version, and — the one that fails
silently otherwise — checks that the cache directory is actually writable. Every
line it can print is in [docs/health.md](docs/health.md).

---

## Contributing

Clone the repository and either symlink it or add it to your runtime path.

```bash
nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
     -c "luafile TESTS/run.lua" -c "qa!"
```

The suite is framework-free and needs no ffmpeg: what it asserts is argument
order, offset arithmetic and cache-key separation, all of which are pure
functions for exactly that reason.

Pull requests very welcome.

---

## Feedback

Your feedback is very welcome. Use the
[issue tracker](https://github.com/StefanBartl/media.nvim/issues) to report
bugs, suggest features or ask usage questions; anything more open-ended fits a
[discussion](https://github.com/StefanBartl/media.nvim/discussions).

If you find this plugin useful, a ⭐ on GitHub supports its development.

---

## License

MIT — see [LICENSE](LICENSE).
