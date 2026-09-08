# Installation

## Requirements

| | |
| --- | --- |
| Neovim | **0.10+** (`vim.system`, `vim.uv`) |
| [lib.nvim](https://github.com/StefanBartl/lib.nvim) | required |
| `ffmpeg` + `ffprobe` | required — one install, both binaries |

```bash
winget install Gyan.FFmpeg          # Windows
brew install ffmpeg                 # macOS
sudo apt install ffmpeg             # Debian / Ubuntu
scoop install ffmpeg                # Windows, scoop
```

After a Windows install, restart the terminal: winget and scoop extend the *user*
PATH, and every already-running process inherited its copy at login. The plugin
probes both shim directories anyway, so it usually finds ffmpeg before you
notice — but `:checkhealth media` is the way to be sure.

## lazy.nvim

```lua
{
  "StefanBartl/media.nvim",
  dependencies = { "StefanBartl/lib.nvim" },
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
  "StefanBartl/media.nvim",
  requires = { "StefanBartl/lib.nvim" },
  config = function()
    require("media").setup()
  end,
})
```

## Without a plugin manager

```bash
git clone https://github.com/StefanBartl/media.nvim \
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
