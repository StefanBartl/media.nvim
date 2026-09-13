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
as a PNG on disk. Anything that can draw a picture can then show a video —
which was, until now, everywhere just a size in bytes and the word "binary".

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
> dependency — see [Requirements](docs/installation.md#requirements).

---

## Documentation

Start at [docs/README.md](docs/README.md), which says what is where and which
question each page answers.

**The Basics**

- [Requirements](docs/installation.md#requirements) — Neovim version, required plugins and CLI tools.
- [Installation](docs/installation.md) — plugin managers and load-trigger variants.
- [Quickstart](docs/quickstart.md) — the first thing to run after installing.

**Configuration**

- [What you get with the defaults](docs/what-you-get.md) — the default keymaps and commands at a glance.
- [All options](docs/configuration.md) — every `setup()` option and its default.
- [Commands](docs/commands.md) / [Bindings cheatsheet](docs/BINDINGS.md)

**The Rest**

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
