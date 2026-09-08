# Roadmap

What is deliberately not here yet, and what it would cost. Ordered by how likely
it is to be built, not by size.

---

## Frame stepping — a poster frame you can scrub

**The idea.** The float shows a still; `]` and `[` step forward and back by five
seconds, re-rendering. A percentage jump (`5` → 50%) lands anywhere. It is not
playback and does not pretend to be — it is a poster frame with a cursor.

**What it costs.** Nothing new in this plugin: `frame(path, { at = t })` already
does the work and already caches per offset, so a second pass over the same
positions is instant. What is missing is the *state* — which offset a given
window is currently showing — and that belongs to the consumer, not here. A
window is the consumer's, and two consumers stepping the same file should not
share a cursor.

**The one thing this plugin should add:** a prefetch hint, so stepping forward
can render `t + 5` while the reader looks at `t`. Roughly ten lines, and it makes
the difference between a step that feels instant and one that feels like a
quarter-second wait.

---

## Block-graphics playback — built

**Status 2026-09-08.** All three halves exist now. The decode is
`media.frames()`, one ffmpeg pass, cancellable, cached like everything else.
The drawing is `images.blocks` in images.nvim. The consumer — transport
state, a timer, a control row — is `hover.nvim`'s `preview.playback`
(`hover.nvim@200ddff`, refined in `hover.nvim@8ccdd23` and `@beb4051`): the
frame-stepping section above argued that state belongs to whoever owns the
window, and it does, just in the other repository rather than this one.

**Sound followed the same split, and is built too** (`media.core.audio`,
this repository; the polling side in `hover.nvim@preview.playback`). It is
its own subsection below the waveform/spectrogram ideas, since the design
turned out to have nothing to do with extracting a WAV.

Measured end to end on this machine, a 640x360 clip at 80x36 cells:

| | |
|---|---|
| `media.frames` — 24 stills, one ffmpeg pass | 168 ms (3 ms on a cache hit) |
| `images.blocks.sample` — all 24 into cells, one ImageMagick pass | 153 ms |
| `images.blocks.paint` — one frame | 4.6 ms → a 218 fps ceiling |
| request to first frame on screen | **325 ms** |
| highlight groups for the whole run | 637, against a hard ceiling of 19 602 |

The paragraph below was written before any of that was measured, and one
sentence in it turned out to be the important one: the ImageMagick read had
to be batched. It is — one call for the run rather than one per frame is
186 ms against 1593 ms. The other half of the warning was misplaced, though:
the thing that nearly sank the approach was not throughput but
`nvim_set_hl`'s hard ceiling, which a truecolour cell grid reaches in seven
noisy frames. Quantising is what bounds it.

**The original note, for the reasoning:**

**The idea.** Extract frames at 8–12 fps, convert each to coloured block
graphics, and swap buffer lines on a timer. It is *text* — one `█` per cell with
its own highlight — so it collides with no terminal graphics protocol and
survives every Neovim redraw. It genuinely plays, at low resolution and without
sound.

**Why the obvious approach does not work.** The path that draws real pictures is
OSC 1337, and it carries a whole base64 payload per write with no notion of a
frame or a placement id. Twelve frames a second of a 500x300 still is roughly
half a megabyte per second through `nvim_ui_send` — and Neovim repaints over
anything drawn between its own redraws, so an animation loop is in a permanent
race with the redraw cycle. The Kitty graphics protocol has animation frames and
would be the right tool, but on Windows in WezTerm nothing sent from inside
Neovim renders through it at all (measured 2026-08-05); only OSC 1337 arrives.

**What it costs.** One ffmpeg run to extract N frames (cheap, one process for all
of them), then one ImageMagick pixel read per frame to get the cell colours —
which is the expensive part and would have to be batched into a single call
rather than one per frame. `images.ascii` already does the single-image version
of exactly this, so the drawing half exists. Realistically: a prototype, and an
honest one — not a feature that should be default-on.

---

## Audio

**Waveform.** `ffmpeg -filter_complex showwavespic` produces a PNG of the
waveform in one pass. It is the audio equivalent of the contact sheet, it fits
`frame`'s shape exactly, and it would give an mp3 without cover art something to
show.

**Spectrogram.** `showspectrumpic`, same shape. Useful to fewer people, free once
the waveform exists.

**Sound for a played run — built.** The naive design has the picture lead — a
Lua timer ticks, draws a frame — and then needs sound synchronised to a timer
in an editor process, which is not a clock worth trusting. `media.core.audio`
inverts it: `mpv --no-video` plays the file over its own JSON IPC socket
(`--input-ipc-server`), and the timer on the other side asks it *where it
is* once per tick rather than counting. A late tick just asks again and
paints whichever frame the answer belongs to — it cannot accumulate a lag
the way two free-running clocks racing each other would. `ffplay` was
considered and ruled out: it never reports its position, so this specific
trick is not available with it. No mpv on PATH is not an error — a played
run is silent exactly as it was before this existed.

---

## Transcription — the other half this plugin was named for

This repository is called `media.nvim` rather than `frames.nvim` because the
concept it came out of has a second half:
[`MEDIA-TO-TEXT.md`](https://github.com/StefanBartl/nvim) in the configuration's
roadmap. That document's finding was that OCR (`images.ocr`) and PDF extraction
(`pdfport`) already exist, and the one real gap in the ecosystem is **audio and
video to text** — no ffmpeg, no whisper, no timestamp data model anywhere.

The ffmpeg half of that gap is now closed by this plugin: extracting a WAV for a
speech model is the same `vim.system` shape as extracting a frame, against the
same binary, with the same availability check and the same cache.

What is left, in order:

1. **`media.audio(path, cb)`** — a 16 kHz mono WAV in the cache. Small; it is
   `frame.lua` with a different filter chain.
2. **`media.transcribe(path, cb)`** — a backend chain over `whisper.cpp` /
   `faster-whisper`, in the shape `pdfport.core.registry` already establishes
   (registry, availability per backend, fallback chain, disk cache). This is the
   large one: model downloads in the gigabyte range and jobs measured in minutes
   need progress reporting and cancellation, neither of which exists here yet.
3. **Segments → SRT/VTT.** A timestamp data model, which nothing in the
   ecosystem has.
4. **Translation** is explicitly *not* this plugin's job.
   [language.nvim](https://github.com/StefanBartl/language.nvim) already answers
   "which lines of this file are prose?" for code, and a subtitle file asks
   exactly that question — translate `00:00:04,120 --> 00:00:07,300` and the file
   is broken. The clean cut is in the tooling anyway: whisper's own
   `--task translate` can only produce English.

---

## Deliberately not planned

**A `BufReadCmd` for media files.** Claiming `*.mp4` globally fights netrw, oil
and every file tree with its own opinion, and turns a `:e` typo into a decode. A
consumer that wants it builds it out of `media.frame` in three lines and owns the
decision — see `lua/media/bindings/autocmds.lua`.

**Thumbnail generation for directories.** That is a file browser's feature built
on this plugin's API, not a feature of this plugin.

**A second renderer.** ImageMagick, GStreamer and mpv can all produce a still.
None of them can produce one ffmpeg cannot, and a backend chain whose branches
are indistinguishable is complexity without an answer — the opposite of
`pdfport`, where seven backends genuinely differ in what they can read.

---

## Literatur und Referenzen

- [FFmpeg documentation — `-ss` as an input vs. output option](https://ffmpeg.org/ffmpeg.html#Main-options),
  and the `fps`, `tile`, `scale` and `showwavespic` filters in
  [ffmpeg-filters](https://ffmpeg.org/ffmpeg-filters.html).
- [FFprobe documentation](https://ffmpeg.org/ffprobe.html) — `-show_streams`,
  `-show_format`, and the `side_data_list` display matrix.
- [ISO/IEC 14496-12](https://www.iso.org/standard/83102.html) — the ISO base
  media file format, where the display matrix that carries rotation is defined.
- [iTerm2 inline images protocol (OSC 1337)](https://iterm2.com/documentation-images.html)
  — the format that reaches the terminal from inside Neovim.
- [Kitty graphics protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) —
  including its animation extension, and why it is not an option here.
- `pdfport.nvim` `docs/architecture.md` — the backend-registry pattern this
  plugin's transcription half would follow.
