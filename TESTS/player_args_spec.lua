-- The mpv argument order for a windowed player.
--
-- Pure function, same reasoning as audio_args_spec: a flag in the wrong place
-- (or a missing `--`) is invisible until the one file whose name starts with a
-- dash is read as an option, or the window freezes on its last frame because
-- `--keep-open` slipped. The window actually appearing needs a real mpv and a
-- display and is not what this suite is for — see `media.core.player`'s header
-- for why a window is the answer to "make it play" at all.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local player = require("media.core.player")

  local argv = player.args({
    mpv = "mpv",
    path = "/tmp/clip.mp4",
    at = 12.5,
    autofit = "80%x80%",
    ontop = true,
  })

  H.eq(argv[1], "mpv", "the binary leads")
  H.ok(H.index_of(argv, "--force-window=immediate"), "a window before the first frame decodes")
  H.ok(H.index_of(argv, "--no-terminal"), "this mpv has no console of its own")
  H.ok(H.index_of(argv, "--keep-open=no"), "a player closes at end of file, it does not freeze")
  H.ok(H.index_of(argv, "--ontop"), "kept above the terminal, which cannot foreground it")
  H.ok(H.index_of(argv, "--autofit-larger=80%x80%"), "the size hint is passed through")
  H.ok(H.index_of(argv, "--start=12.5"), "the offset is passed through, not rounded")
  H.eq(argv[#argv], "/tmp/clip.mp4", "the file is last, like every other argv in this plugin")
  H.eq(argv[#argv - 1], "--", "and behind `--`, so a name beginning with `-` is still a file")
  H.before(argv, "--start=12.5", "--", "the seek is a flag, before the file separator")

  -- No offset, no `--start`: `at = nil` and `at = 0` are both "the beginning".
  local from_start = player.args({ mpv = "mpv", path = "/tmp/c.mp4", autofit = "" })
  local has_start = false
  for _, a in ipairs(from_start) do
    if a:match("^%-%-start=") then has_start = true end
  end
  H.falsy(has_start, "no offset given, no --start")

  local at_zero = player.args({ mpv = "mpv", path = "/tmp/c.mp4", at = 0, autofit = "" })
  has_start = false
  for _, a in ipairs(at_zero) do
    if a:match("^%-%-start=") then has_start = true end
  end
  H.falsy(has_start, "at = 0 is the beginning, not a seek")

  -- An empty autofit is "let mpv/the platform decide": no size hint, and so no
  -- `--geometry` either, since the two go together.
  H.falsy(H.index_of(from_start, "--geometry=50%:50%"), "no autofit, no forced geometry")
  H.ok(
    H.index_of(
      player.args({ mpv = "mpv", path = "/tmp/c.mp4", autofit = "70%x70%" }),
      "--geometry=50%:50%"
    ),
    "an autofit centres the window"
  )

  -- `ontop = false` is a real choice, not "unset": a user who does not want a
  -- window that stays on top must be able to say so.
  local not_ontop = player.args({ mpv = "mpv", path = "/tmp/c.mp4", ontop = false })
  H.falsy(H.index_of(not_ontop, "--ontop"), "ontop can be turned off")

  -- `mute` plays the picture with the sound off — for a caller that wants a
  -- preview without noise, not a silent file.
  local muted = player.args({ mpv = "mpv", path = "/tmp/c.mp4", mute = true })
  H.ok(H.index_of(muted, "--mute=yes"), "mute is asked for when the caller wants it")
  local loud = player.args({ mpv = "mpv", path = "/tmp/c.mp4" })
  H.falsy(H.index_of(loud, "--mute=yes"), "and never otherwise")

  -- Extra args land verbatim, before the file separator so they cannot be
  -- mistaken for the path.
  local extra =
    player.args({ mpv = "mpv", path = "/tmp/c.mp4", extra = { "--loop", "--speed=1.5" } })
  H.ok(H.index_of(extra, "--loop"), "an extra arg is appended")
  H.before(extra, "--speed=1.5", "--", "extra args precede the file separator")

  -- `screen` is what `--geometry`'s and `--autofit-larger`'s percentages
  -- resolve against: without it both key off whatever mpv treats as screen
  -- 0, which on a multi-monitor machine is not necessarily the one a caller
  -- (hover.nvim, matching the monitor a hover was played from) meant.
  local screened =
    player.args({ mpv = "mpv", path = "/tmp/c.mp4", screen = 1, autofit = "80%x80%" })
  H.ok(H.index_of(screened, "--screen=1"), "the target screen is passed through")
  H.before(
    screened,
    "--screen=1",
    "--geometry=50%:50%",
    "the screen is named before geometry resolves against it"
  )
  local unscreened = player.args({ mpv = "mpv", path = "/tmp/c.mp4" })
  local has_screen = false
  for _, a in ipairs(unscreened) do
    if a:match("^%-%-screen=") then has_screen = true end
  end
  H.falsy(has_screen, "no screen given, no --screen -- mpv's own default applies")
end
