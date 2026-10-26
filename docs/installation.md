# Installation

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** (`vim.system`, `vim.uv`) |
| [lib.nvim](https://github.com/WKDSteve/lib.nvim) | recommended — soft dependency, see below |
| `ffmpeg` + `ffprobe` | required — one install, both binaries |
| `mpv` | optional — sound for a played run, and `:Media window` / `media.play_window()` |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp)'s `whisper-cli` + a GGML model | optional — `media.transcribe()` / `:Media transcribe` |
| **or** [faster-whisper](https://github.com/SYSTRAN/faster-whisper)'s `whisper-ctranslate2` | optional — the same, through CTranslate2; the faster of the two Python engines |
| **or** [openai-whisper](https://github.com/openai/whisper)'s `whisper` | optional — the same, through PyTorch; any one engine is enough |

Every place this plugin reaches for lib.nvim falls back to a plain Neovim
equivalent when it is missing (`:checkhealth media` reports this under
"optional integrations", never as an error) — but the fallback is visibly
poorer: `:Media` loses tab completion, the float dashboard becomes a
`vim.notify` list, and a transcription runs with no progress indicator or
cancel key. Install it unless you have a specific reason not to.

```bash
winget install Gyan.FFmpeg          # Windows
brew install ffmpeg                 # macOS
sudo apt install ffmpeg             # Debian / Ubuntu
scoop install ffmpeg                # Windows, scoop

winget install mpv-player.mpv       # Windows  — optional
brew install mpv                    # macOS    — optional
sudo apt install mpv                # Debian / Ubuntu — optional
```

`whisper-cli` has no package-manager install on any platform this plugin
targets — build it from [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
(`cmake -B build && cmake --build build`; on Windows with MinGW add
`-DCMAKE_EXE_LINKER_FLAGS="-static -static-libgcc -static-libstdc++"`, or the
binary may load another program's `libstdc++-6.dll` from PATH and die before
printing anything — reported as "a DLL it loaded is the wrong version") and download a GGML model
separately (e.g. `ggml-base.en.bin`). Point `transcribe.whisper_cpp.model` at
it; `bin["whisper-cli"]` only if the binary lands off PATH. Neither the
binary nor a model is ever fetched by this plugin — `:checkhealth media`
reports what is missing.

faster-whisper and openai-whisper are the alternatives when building
whisper.cpp is not an option — faster-whisper is several times quicker on a
CPU and needs no ffmpeg of its own:

```bash
pip install -U whisper-ctranslate2  # faster-whisper; or: pipx install whisper-ctranslate2
pip install -U openai-whisper       # or: pipx install openai-whisper
brew install openai-whisper         # macOS
```

Both fetch models on first use; the plugin refuses that until you set
`transcribe.faster_whisper.allow_download` / `transcribe.openai_whisper.allow_download`
to `true`. The paragraph below is about openai-whisper.

It needs ffmpeg on PATH, which this plugin arranges for the process it
starts, and it fetches a model by name the first time it is used. The plugin
refuses that until you set `transcribe.openai_whisper.allow_download = true`,
or until you have run `whisper --model <name>` once yourself. With the default
`transcribe.engine = "auto"`, the fastest engine that is ready gets used.

After a Windows install, restart the terminal: winget and scoop extend the *user*
PATH, and every already-running process inherited its copy at login. The plugin
probes both shim directories anyway, so it usually finds ffmpeg before you
notice — but `:checkhealth media` is the way to be sure.

## lazy.nvim

```lua
{
  "WKDSteve/media.nvim",
  dependencies = { "WKDSteve/lib.nvim" },
  event = "VeryLazy",
  opts = {},
}
```

### Which load trigger

| Trigger | When |
| --- | --- |
| `event = "VeryLazy"` | you want the keymaps. They have to exist before you press one, so a `cmd` trigger cannot bind them. |
| `cmd = { "Media" }` | you only ever type the command. Cheapest — nothing loads until then. |
| `lazy = false` | another plugin consumes `require("media")` at startup. Rare: consumers should `pcall(require, "media")` at the point of use instead. |

The plugin file (`plugin/media.lua`) registers nothing at startup on purpose:
everything comes from `setup()`, which `opts = {}` runs for you.

## packer.nvim

```lua
use({
  "WKDSteve/media.nvim",
  requires = { "WKDSteve/lib.nvim" },
  config = function()
    require("media").setup()
  end,
})
```

## Without a plugin manager

```bash
git clone https://github.com/WKDSteve/media.nvim \
  ~/.local/share/nvim/site/pack/plugins/start/media.nvim
```

Then `require("media").setup()` somewhere in your configuration. `setup()` is
optional for the library API — `require("media").frame(...)` works without it —
but the command and the keymaps come from it.

## Verifying

```vim
:checkhealth media
```

See [health.md](health.md) for every line it can print.
