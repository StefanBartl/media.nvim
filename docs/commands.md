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

## `:Media dashboard [cfile|cwd] [path=<dir>]`

One list across every image, PDF, audio file and video below a scope, and
whether each one's text is there:

```
  image  assets/error.png        1920x1080  ✓ ocr (3 days old)
  audio  notes/2026-08-11.m4a    6:44       — transcript: missing
  pdf    docs/spec.pdf                      — text: missing
  video  talks/keynote.mp4       41:07      ! transcript: stale
  video  talks/standup.mp4       14:32      ✓ transcript (2 hours old)
```

**The last column is why this exists.** `—` is a job not yet done. `!` is a
file on disk quietly answering questions about a version of the source that no
longer exists — the one that produces wrong answers without ever looking wrong.
The title counts them: `media: ~/work — 12 files, 2 stale, 5 missing`.

### Scope

The same three words as `:Image pickers` and `language.nvim`, with the same
three meanings:

| Scope | Means |
| --- | --- |
| `cwd` (the default) | the working directory |
| `cfile` | the directory of the file in the current buffer |
| `path=<dir>` | an explicit directory |

`.git` and `node_modules` are never descended into; `hub.exclude` adds more,
and `hub.max_entries` bounds a scan that turns out to cover a home directory.

### Keys

| Key | Does |
| --- | --- |
| `<CR>` | the obvious thing (see below) |
| `<Tab>` | mark this row, and step down |
| `a` | choose an action for this row, or for the marked set |
| `o` | open the existing text |
| `gf` | open the source file |
| `p` | describe it, as `:Media probe` does |
| `r` | rescan |
| `q` / `<Esc>` | close |
| right mouse | the same actions `a` offers |

**`<CR>` is the obvious thing, and never wasted work.** A row whose text is
missing or stale gets made; a row whose text is current gets opened. That
asymmetry is the point — a `<CR>` that re-transcribed a file with a current
transcript would spend minutes producing what was already on disk, and one that
only ever opened would make this a list you cannot act on.

A **stale** sidecar opens anyway, with a warning: it is still the text that is
there, and refusing would hide the thing the column exists to point at.

### Acting on several rows at once

`<Tab>` marks a row and steps down, so marking a run of files is
`<Tab><Tab><Tab>`. With rows marked, `<CR>` and `a` act on the marked set
instead of the row under the cursor, and only the actions a *batch* means
anything for are offered — "open the source file" over twelve rows is twelve
windows, not a batch.

The batch runs **sequentially**, with **one** progress handle over the whole
run: each of these is a whole external process, and twelve at once would put
twelve of them on the machine competing for the same cores. The indicator shows
a real ratio (`4/12`), which it can here and cannot inside a single
transcription — *files done of files asked* has a denominator, where "38%
through this audio" would be a guess.

A failure does not stop the batch: a file that cannot be read is one row's
problem, and eleven transcripts are worth more than an error message. Whatever
failed is listed by name at the end. `progress_style = "float"` gives the batch
a cancel key, which stops it after the file currently in flight.

### Actions

| Kind | Actions |
| --- | --- |
| image | OCR → sidecar / buffer |
| pdf | Extract text → sidecar / buffer |
| audio, video | Transcribe → sidecar / buffer / `.srt` / `.vtt`, and transcribe + translate to English |
| any | Open the existing text · open the source file · describe it |

**An action whose tool is missing is still listed**, with the reason beside it;
picking it explains rather than runs. Hiding it would answer "what can I do
right now" when the question a dashboard is asked is "what is possible here" —
and nobody ever learned a feature existed from a menu that did not mention it.

### A sidecar is a plaintext copy, and a batch makes forty of them

`:Media text` and the dashboard's actions write what they read to a file next
to the source. For a screenshot of a terminal, a scan of a letter or a recorded
call, that sidecar is a **searchable plaintext copy of whatever was in it** —
and `<Tab>` over forty marked rows makes forty of them in one keystroke.

Nothing here is doing anything surprising; it is the same thing
`casedesk.nvim`'s OCR has always done, and the sidecars sit in plain sight next
to their sources rather than somewhere a `grep` would miss. But the dashboard
makes it a bulk operation, which is worth knowing before pointing it at a
directory you have not looked at.

The **stale** marker is the other half of this. If a source is later redacted
in place (`:Image redact` does exactly that), its sidecar still holds the text
from before — and the `!` is what says so rather than letting the old text pass
as current.

### Not offered here, on purpose

The roadmap's action table also lists *page → PNG* for a PDF and *extract
audio* for a video. Both are real, and both are somebody else's verb —
`pdfport.render_page` and an ffmpeg call that writes a file rather than a cache
entry. Neither has a home in this plugin's public surface yet, and inventing
one from the dashboard would put the feature in the wrong place.

### The detail column fills in after the list appears

The scan itself starts no processes: five hundred files would be five hundred
`ffprobe`s before a single row was drawn. So the list is on screen at once with
whatever is already cached, and up to fifty probes then fill the middle column
in and redraw. A PDF's page count stays blank — that is `pdfinfo`'s answer, and
this plugin will not shell out to it behind pdfport's back.

## `:Media text [path] [out=]`

**One verb, whatever the file is.** This is the reason the plugin is called
`media` and not `transcribe`: an image, a PDF, an audio file and a video are
four different tools away from being text, and remembering which is which is
not work worth doing.

| Kind | Goes to | Produced by |
| --- | --- | --- |
| image | `images.ocr.run` | tesseract, through images.nvim |
| pdf | `pdfport.extract` | whichever of pdfport's backends can read it |
| audio, video | this plugin's own dispatcher | whisper.cpp |
| anything else | nothing — it says so | — |

`out=` is the same argument `:Media transcribe` takes, but **the modes on
offer depend on the kind**: `srt` and `vtt` need timestamps, so they are
available for audio and video and nowhere else. A page of OCR has no segments
to put a cue around.

| Kind | `out=` |
| --- | --- |
| image | `buffer`, `sidecar` (`<file>.ocr.md`) |
| pdf | `buffer`, `sidecar` (`<file>.text.md`) |
| audio, video | `buffer`, `sidecar` (`<file>.transcript.md`), `srt`, `vtt` |

**Three sidecar names, because they are three different operations.** OCR
misreads, transcription mishears, extraction is exact — and the name is the
only warning a reader gets about how much to trust the file. It is also what
lets a corpus tool exclude the two lossy ones and keep the third.

**Every dependency is soft.** No images.nvim costs OCR and nothing else; no
pdfport.nvim costs PDFs and nothing else. What you get instead is the reason
and the fix, said before anything starts:

```
images.nvim is not installed — it is the plugin that owns OCR in this ecosystem
tesseract was not found — install tesseract, or set images.nvim's `ocr.bin`
```

Audio and video get the same live indicator, cancel key and `progress_style`
as `:Media transcribe`, because they are the same run.

## `:Media transcribe [path] [engine=] [lang=] [task=] [out=]`

Turns `path`'s speech into text: probes it, extracts a 16 kHz mono WAV,
runs it through the resolved engine, and delivers the result.

| Argument | Takes | Default |
| --- | --- | --- |
| `engine=` | a registered engine id (`whisper_cpp` is the only one in phase 0) | `transcribe.engine` |
| `lang=` | an ISO 639-1 code (`en`, `de`, …), or omit to let the engine detect it | `transcribe.lang` |
| `task=` | `transcribe` (keep the source language) or `translate` (whisper.cpp's own English-only translate) | `transcribe.task` |
| `out=` | `buffer`, `sidecar`, `srt` or `vtt` — see the table below | `transcribe.output` |

### Where the transcript goes

| `out=` | Writes | Why you would |
| --- | --- | --- |
| `buffer` | nothing — a scratch window | The default: a machine transcript is worth reading before it is worth keeping |
| `sidecar` | `<file>.transcript.md` | The convention this ecosystem's OCR already established; greppable, and `:Translate` handles it |
| `srt` | `<file>.srt` | SubRip — what every player reads |
| `vtt` | `<file>.vtt` | WebVTT — what a browser reads |

Both subtitle suffixes are appended to the *full* file name, so `talk.mp4`
becomes `talk.mp4.srt`. `talk.mp4` and `talk.mov` in one directory therefore
cannot overwrite each other's subtitles, and mpv and VLC autoload that form
regardless.

An `out=` this command does not recognise is rejected **before** the run
starts rather than after it: transcription is minutes, and a typo discovered
at the end costs the whole wait.

### While it runs

With lib.nvim installed the command shows a live indicator: which step it is
on, which engine is spending the time, and how long it has been running —
`transcribing with whisper_cpp — 2:41`. `progress_style` picks how that is
drawn, and `"float"` is the style that also gives the run a **cancel key**:
focus the window and press `<Esc>` in normal mode and the whole pipeline
stops, ffmpeg included.

**No percentage, and that is deliberate.** whisper.cpp reports no progress of
its own, and a figure derived from the audio duration would be calibrated to
whichever machine, model and thread count measured it. A wrong percentage is
worse than none, because it is the one a reader plans around.

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
