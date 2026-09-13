# Quickstart

Put the cursor on a path to a video — in a file tree, in a markdown link, in a
directory listing — and press `<leader>Mp`. Or name it:

```vim
:Media probe ~/Videos/holiday.mp4
```

Then the picture:

```vim
:Media frame                  " poster frame of the file under the cursor
:Media frame at=50% width=1200
:Media sheet rows=4 cols=5    " the whole file as a grid
```

And to actually watch it:

```vim
:Media window                 " a real mpv window, from the start
:Media window at=90           " …or ninety seconds in
:Media play                   " …or hand it to the system's player
```

Verify your setup any time with:

```vim
:checkhealth media
```

See [what-you-get.md](what-you-get.md) for the rest of the surface at a
glance, or [commands.md](commands.md) for the full reference.
