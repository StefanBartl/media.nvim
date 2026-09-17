# media.nvim — bindings cheatsheet

Everything this plugin binds, in one place.

## Keymaps

Bound globally by `setup()`. Each key acts on the path under the cursor
(`<cfile>`), falling back to the current buffer's own name.

| Key | Mode | Action |
| --- | --- | --- |
| `<leader>Mp` | n | describe the media file — duration, size, codecs, resolution |
| `<leader>Mf` | n | poster frame, rendered and shown |
| `<leader>Ms` | n | contact sheet of the whole file |
| `<leader>Mo` | n | play in an external player |

Change or disable individually:

```lua
require("media").setup({
  keymaps = {
    frame = "<leader>vf",   -- rebind
    sheet = false,          -- disable this one
    -- preset = false,      -- bind nothing at all
  },
})
```

`<leader>M` is the which-key group prefix, labelled `media`.

## Commands

One verb with routes, built through `lib.nvim`'s usercmd composer, so every
subcommand and every path argument completes with `<Tab>`.

| Command | Does |
| --- | --- |
| `:Media [path]` | describe the file (same as `probe`) |
| `:Media probe [path]` | describe the file |
| `:Media frame [path] [at=…] [width=…]` | render and show a poster frame |
| `:Media sheet [path] [rows=…] [cols=…] [width=…]` | render and show a contact sheet |
| `:Media waveform [path] [width=…] [height=…]` | render and show a waveform picture |
| `:Media spectrogram [path] [width=…] [height=…]` | render and show a spectrogram |
| `:Media transcribe [path] [engine=] [lang=] [task=] [out=]` | speech to text — a buffer, a `.transcript.md` sidecar, or `.srt`/`.vtt` subtitles |
| `:Media engines` | list registered transcription engines and their availability |
| `:Media play [path]` | hand the file to an external player |
| `:Media window [path] [at=…]` | play in a real mpv window, from `at` |
| `:Media cache clear` | delete every rendered still, WAV and cached transcript |
| `:Media health` | `:checkhealth media` |

`at=` takes seconds (`at=27.5`), a percentage of the duration (`at=50%`) or a
timestamp ffmpeg understands (`at=00:01:23.5`).

Omitting `[path]` uses `<cfile>`, then the current buffer's name.

## Autocommands

Group `MediaNvim`.

| Event | Does |
| --- | --- |
| `VimResume` | forgets where ffmpeg was (or was not) found, so installing it while Neovim is open takes effect |

There is deliberately **no** autocommand that intercepts opening a media file.
Claiming `BufReadCmd *.mp4` globally fights every file tree that has its own
opinion, and turns a `:e` typo into a decode. A consumer that wants it builds it
out of `media.frame` in three lines and owns the decision.
