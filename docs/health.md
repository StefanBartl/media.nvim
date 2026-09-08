# `:checkhealth media`

Five sections, in the order things go wrong.

## `media.nvim: toolchain`

| Line | Means |
| --- | --- |
| `ffmpeg found: <path>` | either the bare name (it is on PATH) or the absolute path a probe turned up |
| `ffprobe found: <path>` | same |
| `ffmpeg not found` | with the install command for your platform, and the `bin.ffmpeg` escape hatch |
| `ffmpeg version …` | the first line of `ffmpeg -version`, so a very old build is visible |
| `ffmpeg was found but would not report its version` | the file exists and is not a working ffmpeg — a stale shim, or a wrong `bin.ffmpeg` |

Both binaries are required, not either: a poster frame needs a duration from
`ffprobe` to resolve a percentage offset, and a probe without `ffmpeg` can
describe a file but not show it.

## `media.nvim: cache`

| Line | Means |
| --- | --- |
| `cache directory is writable: <dir>` | a file was created there and removed again |
| `cache directory is not writable` | set `cache.dir` somewhere else, or fix the permissions |
| `the cache directory could not be created` | the parent does not exist or is not writable |

This section exists because its failure is silent otherwise: a read-only cache
directory produces *"no frame was written"* from a renderer that ran perfectly.

## `media.nvim: optional integrations`

| Line | Means |
| --- | --- |
| `lib.nvim found` | keymap registry, `:Media` tab completion, scratch windows |
| `lib.nvim not installed` | the plugin still works; the command loses completion and the keys lose the registry's diagnostics |
| `images found` | rendered stills are drawn in the terminal |
| `images not installed` | stills open in the system image viewer instead |

## `media.nvim: mpv`

| Line | Means |
| --- | --- |
| `mpv found: <path>` | `media.audio` can give a played run sound, and `:Media window` can open a real player window |
| `mpv not found` | with the install command for your platform, and the `bin.mpv` escape hatch — a played run stays silent and `:Media window` cannot open, neither an error |

Unlike the toolchain section, `mpv` missing is `h_info`, not `h_err`: nothing
here requires it, and everything that uses it degrades to exactly what it did
before this existed.

## `media.nvim: what is claimed`

The video and audio extension lists, and what `:Media play` will launch.

On Windows this section also prints the note about a window started from a
terminal Neovim opening behind the terminal — it is not a defect, and knowing
that in advance saves an issue. `:Media window` passes `--ontop` so the window
stays visible regardless; see [configuration.md](configuration.md#window).
