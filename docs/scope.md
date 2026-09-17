# What it does and what not

A handful of answers, and nothing else.

| | |
| --- | --- |
| **Describe** | `ffprobe` in one process, flattened into one record: duration, size, bitrate, resolution, frame rate, codecs, channels. |
| **Poster frame** | One still, seeked to a configurable offset, scaled and cached as a PNG. |
| **Contact sheet** | The whole running time as a grid of stills — one render, one picture, no playback. |
| **Frame run** | A stretch of the file as a numbered sequence of stills, one ffmpeg pass, cancellable — what a consumer that can draw cells turns into moving picture. |
| **Waveform / spectrogram** | A picture of the audio track — the sound equivalent of a poster frame, for a file (an mp3 without cover art) that has no picture to show one of. |
| **Speech to text** | `media.transcribe()` / `:Media transcribe` — probe, extract a WAV, run it through a local transcription engine (`whisper.cpp`; one engine so far), deliver a buffer, a `.transcript.md` sidecar, or SRT/VTT subtitles. See [commands.md](commands.md#media-transcribe-path-engine-lang-task-out). |
| **Anything to text** | `:Media text` — one verb across all four kinds: an image goes to images.nvim's OCR, a PDF to pdfport, audio and video to the transcription engine above. This plugin is the one place in the ecosystem allowed to `pcall` its way to all three, which is why every dependency here stays soft. |

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
plugin drives over its JSON IPC socket. It is smooth on a fast terminal; where
the editor's own redraw is the bottleneck (Windows/WezTerm was measured at about
one repaint a second, whichever way the paint was written) it is a slideshow,
and no amount of tuning the paint changes that — the picture *is* the redraw.

For that case there is `media.play_window()` (`:Media window`): a real mpv
window, opened on the file at a given offset and stopped again by a handle the
caller holds. mpv decodes, scales, syncs the sound and draws with the GPU, with
no editor redraw in the loop — `hover.nvim` uses it for the `<CR>` in a video
hover. `:Media play` is the third answer, and the least owned: hand the file to
whatever the user configured, or to the system's default handler. `hover.nvim`
falls back to it too, for the same `<CR>`, on a machine without mpv on PATH.
