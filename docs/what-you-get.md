# What you get with the defaults

| Key / command | Where | Does |
| --- | --- | --- |
| `<leader>Mp` | normal | describe the file under the cursor |
| `<leader>Mf` | normal | poster frame |
| `<leader>Ms` | normal | contact sheet |
| `<leader>Mo` | normal | play in an external player |
| `:Media [path]` | command | the same description, by name |
| `:Media waveform [path]` / `:Media spectrogram [path]` | command | a picture of the audio track |
| `:Media text [path]` | command | anything to text — image → OCR, PDF → extract, audio/video → transcribe |
| `:Media transcribe [path]` | command | speech to text — a buffer, a `.transcript.md` sidecar, or `.srt`/`.vtt` subtitles |
| `:Media engines` | command | list transcription engines and their availability |
| `:Media window [path] [at=]` | command | play in a real mpv window, from `at` |
| `:Media cache clear` | command | throw away every rendered still, WAV and cached transcript |

The full set is the [bindings cheatsheet](BINDINGS.md).
