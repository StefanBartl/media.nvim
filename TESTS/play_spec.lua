-- media.core.play: the argument validation and configured-player resolution
-- that run before anything is actually spawned. `vim.system` itself is never
-- exercised here — the whole point of `M.play` is that the player outlives
-- the call, and a test that actually launched one would leak a process.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local play = require("media.core.play")
  local config = require("media.config")

  -- ── M.play rejects an unusable path before anything is resolved ────────
  -- A real caller could pass nil (e.g. a keymap with nothing under the
  -- cursor); the annotation is non-nilable because every *documented* caller
  -- guards it first, so the nil case is exercised here regardless.
  ---@diagnostic disable-next-line: param-type-mismatch
  local ok1, err1 = play.play(nil)
  H.eq(ok1, false, "a nil path is rejected")
  H.match(err1, "no path given", "...with a message naming the problem")

  local ok2, err2 = play.play("")
  H.eq(ok2, false, "an empty path is rejected the same way")
  H.match(err2, "no path given", "")

  -- ── M.player(): no configuration means no configured player, not an
  --    error — the system default is the supported "no config" case ─────
  config.setup({})
  local argv0, perr0 = play.player()
  H.eq(argv0, nil, "nothing configured, nothing resolved")
  H.eq(perr0, nil, "and that is not an error")

  -- ── M.player(): a string is turned into a one-element argv ─────────────
  -- "nvim" is used as the "found on PATH" case rather than mpv/vlc: this
  -- suite is running inside nvim, so it is the one binary guaranteed to be
  -- on PATH without depending on what is installed on the machine.
  config.setup({ player = "nvim" })
  local argv1, perr1 = play.player()
  H.eq(perr1, nil, "a real, found binary resolves without error")
  H.eq_list(argv1, { "nvim" }, "a string config becomes a one-element argv")

  -- ── M.player(): a table config is copied, not aliased ───────────────────
  config.setup({ player = { "nvim", "--headless" } })
  local argv2 = play.player()
  H.eq_list(argv2, { "nvim", "--headless" }, "a table argv is used as given")
  argv2[1] = "mutated"
  local argv2_again = play.player()
  H.eq(argv2_again[1], "nvim", "player() hands out a copy, not the config table itself")

  -- ── M.player(): a binary that cannot be found is a real error ──────────
  config.setup({ player = "__play_spec_missing_binary__" })
  local argv3, perr3 = play.player()
  H.eq(argv3, nil, "an unfindable configured player resolves to nothing")
  H.match(perr3, "not found", "...and says so")
  H.match(perr3, "__play_spec_missing_binary__", "...naming what was configured")

  -- ── M.player(): neither a string nor an argv list is a config error ────
  -- Deliberately an invalid shape, to exercise M.player()'s own guard.
  ---@diagnostic disable-next-line: assign-type-mismatch
  config.setup({ player = 42 })
  local argv4, perr4 = play.player()
  H.eq(argv4, nil, "a number is not a valid player config")
  H.match(perr4, "string or an argv list", "the error explains the two accepted shapes")

  config.setup({ player = {} })
  local argv5, perr5 = play.player()
  H.eq(argv5, nil, "an empty table has no argv[1] to run")
  H.match(perr5, "string or an argv list", "")

  config.setup({})
end
