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

## `:Media play [path]`

Hands the file to the configured `player`, or to the system's default handler.
Fire and forget — this plugin does not own the window and does not stop it.

## `:Media window [path] [at=…]`

Opens the file in a **real mpv window** — video and sound, drawn by mpv with the
GPU, no editor redraw in the loop. `at` is where playback starts: a number of
seconds, a percentage (`50%`), or an ffmpeg timestamp (`00:01:23`), passed
straight to mpv's own `--start`.

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
