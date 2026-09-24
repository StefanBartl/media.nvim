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
[![wkd](https://img.shields.io/badge/wkd-family-c6ff3d)](https://stefanbartl.github.io/wkd/p/media/)

> Part of the [wkd](https://stefanbartl.github.io/wkd/) family — see this plugin's [page](https://stefanbartl.github.io/wkd/p/media/) on the site.

**What is in this media file, one picture of it, and — a video or an audio
file's speech, turned into text.** `ffprobe` says how long, how big and in
which codec; `ffmpeg` produces a poster frame, a contact sheet or a waveform
as a PNG on disk; a local transcription engine turns the speech in it into a
buffer, a `.transcript.md` sidecar, or SRT/VTT subtitles. `:Media text` turns
*any* of the four into text with one verb — an image through images.nvim's OCR,
a PDF through pdfport, audio and video through the transcription engine.
Anything that can draw a picture can
then show a video — which was, until now, everywhere just a size in bytes and
the word "binary".

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
> All of the above are soft, and so is
> [lib.nvim](https://github.com/StefanBartl/lib.nvim) — every place that uses
> it falls back to a plain Neovim equivalent, `:checkhealth media` included.
> It is the one worth having anyway: without it `:Media` loses tab
> completion, the float dashboard becomes a `vim.notify` list, and a
> transcription runs with no progress indicator. See
> [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

### The Basics

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

### Configuration

- [What you get with the defaults](docs/what-you-get.md) — the default keymaps and commands at a glance.
- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)

### The Rest

- [What it does and what not](docs/scope.md) — three answers on what it renders, and why it neither paints nor plays anything itself.
- [Lua API](docs/api.md) — the surface another plugin consumes.
- [Health check](docs/health.md) — what `:checkhealth media` reports, line by line.
- [Contributing](docs/CONTRIBUTING.md)
- [Feedback](https://github.com/StefanBartl/media.nvim/issues)

`:help media` is the same reference inside the editor.

---

## License

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

media.nvim is released under the [MIT License](https://opensource.org/licenses/MIT).
