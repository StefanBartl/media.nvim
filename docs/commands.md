# Command reference

One verb, `:Media`, with routes. Built through `lib.nvim`'s usercmd composer, so
every subcommand and every path argument completes with `<Tab>`. Without
lib.nvim the same subcommands exist with plain completion.

Every path-taking route resolves its target in this order:

1. the explicit `[path]` argument, expanded (`~`, `$VAR`, `%`);
2. `<cfile>` — the path under the cursor, when it names a readable file;
3. the current buffer's own name.

## `:Media [path]`

Describe the file. The same as `:Media probe`, and the root route because it is
the cheapest useful answer — it tells you whether the others are worth asking
for.

## `:Media probe [path]`

Opens a scratch window with the record:

```
holiday.mp4

  container    mov,mp4,m4a,3gp,3g2,mj2
  duration     4:32
  size         100.0 MB
  bitrate      3080 kbit/s

  video
  codec        h264
  resolution   1920x1080
  fps          29.970

  audio
  codec        aac
  channels     2
  sample rate  48000 Hz
```

A field ffprobe could not answer is left out rather than printed as `nil`, and a
section with nothing in it does not appear. `rotation` shows only when there is
one.

## `:Media frame [path] [at=…] [width=…]`

Renders one still and shows it — through images.nvim when installed, else the
system image viewer, else by printing the path.

| Argument | Takes | Default |
| --- | --- | --- |
| `at=` | seconds (`27.5`), a percentage (`50%`), or a timestamp (`00:01:23.5`) | `10%` |
| `width=` | pixels; the height follows the aspect ratio | `800` |

The still is cached, so the second call on the same file with the same arguments
is a `stat` and a draw.

An offset at or past the end of the file is pulled back inside it rather than
producing nothing — the failure that would otherwise read as a broken renderer.

## `:Media sheet [path] [rows=…] [cols=…] [width=…]`

Renders a grid of stills spread evenly over the running time.

| Argument | Takes | Default |
| --- | --- | --- |
| `rows=` | integer | `3` |
| `cols=` | integer | `4` |
| `width=` | pixels for the whole sheet | `1200` |

Needs a duration; a file that reports none says so instead of producing twelve
stills from its first second.

## `:Media waveform [path] [width=…] [height=…]`

Renders a waveform picture of the file's audio and shows it — the sound
equivalent of `:Media frame`, for a file with nothing to show a poster frame
of (an mp3 without cover art, say).

| Argument | Takes | Default |
| --- | --- | --- |
| `width=` | pixels | `1200` |
| `height=` | pixels | `300` |

Needs an audio stream; a file without one says so instead of producing a
blank picture. Reads the whole file once, like `:Media sheet` — there is no
seek to make this cheap, so it is cached the same way and for the same reason.

## `:Media spectrogram [path] [width=…] [height=…]`

Same shape as `:Media waveform`, a different question answered: what
frequencies are in this clip rather than how loud it is at each moment.

| Argument | Takes | Default |
| --- | --- | --- |
| `width=` | pixels | `1200` |
| `height=` | pixels | `300` |

## `:Media transcribe [path] [engine=] [lang=] [task=] [out=]`

Turns `path`'s speech into text: probes it, extracts a 16 kHz mono WAV,
runs it through the resolved engine, and delivers the result.

| Argument | Takes | Default |
| --- | --- | --- |
| `engine=` | a registered engine id (`whisper_cpp` is the only one in phase 0) | `transcribe.engine` |
| `lang=` | an ISO 639-1 code (`en`, `de`, …), or omit to let the engine detect it | `transcribe.lang` |
| `task=` | `transcribe` (keep the source language) or `translate` (whisper.cpp's own English-only translate) | `transcribe.task` |
| `out=` | `buffer` (a scratch window) or `sidecar` (`<file>.transcript.md`) | `transcribe.output` |

Needs `whisper-cli` on PATH (or `bin["whisper-cli"]` configured) and
`transcribe.whisper_cpp.model` set to a GGML `.bin` file — `:checkhealth
media` says which, if either, is missing; neither is ever installed or
downloaded automatically. Cached the same way every other rendering here is,
keyed by the source file's mtime plus the engine/language/task that produced
it — an edited file, a different engine or a different language each get
their own entry.

Every other target language than English goes through
[language.nvim](https://github.com/StefanBartl/language.nvim) afterwards,
not through this command — see ROADMAP.md's "Transcription" section for why
that split is where the capability actually lives, not a preference.

## `:Media engines`

Lists every registered transcription engine and whether it currently reports
itself available — the same check `:Media transcribe` makes before running
one.

## `:Media play [path]`

Hands the file to the configured `player`, or to the system's default handler.
Fire and forget — this plugin does not own the window and does not stop it.

## `:Media window [path] [at=…] [screen=…]`

Opens the file in a **real mpv window** — video and sound, drawn by mpv with the
GPU, no editor redraw in the loop. `at` is where playback starts: a number of
seconds, a percentage (`50%`), or an ffmpeg timestamp (`00:01:23`), passed
straight to mpv's own `--start`. `screen` is which display mpv's `--geometry`
(and `autofit`) percentages resolve against — mpv's own screen index, not
necessarily the one this Neovim happens to be on; try `mpv --screen=<n>` on
its own against a test file to find which number is which monitor.

Unlike `:Media play` this is always mpv, and the window is stopped at `:qa` even
if you never close it. The window is `--ontop` by default because a window
spawned from inside a terminal cannot bring itself to the front on Windows —
`window.ontop = false` turns that off. Size, ontop and extra mpv flags are the
`window` table in [configuration.md](configuration.md#window).

Consumers get the same thing with a handle they can stop early:
`require("media").play_window(path, { at = 90 })`.

## `:Media cache clear`

Deletes every rendered still and forgets every remembered probe. Reports how many
files went.

## `:Media health`

`:checkhealth media`. See [health.md](health.md).
