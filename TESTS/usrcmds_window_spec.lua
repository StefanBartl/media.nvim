-- `:Media window [path] [at=…] [screen=…]`: every key the route parses has to reach
-- `media.play_window`. `screen=` used to be parsed by the route and dropped by `M.run`, so the
-- display it names was never passed on while the option float and the docs promised it.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  local usrcmds = require("media.bindings.usrcmds")
  local media = require("media")

  usrcmds.register()
  H.ok(composer.registry().Media ~= nil, ":Media is registered through the composer")

  local orig = media.play_window
  local calls = {}
  -- No mpv here: what is asserted is only what the command hands to `play_window`.
  media.play_window = function(path, opts)
    calls[#calls + 1] = { path = path, opts = opts }
    return nil, nil
  end

  local function window(args)
    calls = {}
    vim.cmd("Media window /media-spec/clip.mp4 " .. args)
    H.eq(#calls, 1, "`:Media window " .. args .. "` opens exactly one window")
    H.eq(calls[1].path, "/media-spec/clip.mp4", "the path reaches play_window")
    return calls[1].opts
  end

  local run_ok, err = pcall(function()
    -- ── at= and screen= both arrive ────────────────────────────────────────
    local opts = window("at=5 screen=2")
    H.eq(opts.at, 5, "at= reaches play_window as a number")
    H.eq(opts.screen, 2, "screen= reaches play_window as a number")

    -- mpv counts displays from 0, so the first one must not be lost to a falsy check.
    opts = window("screen=0")
    H.eq(opts.screen, 0, "screen=0 (the first display) is passed on")

    -- ── at= keeps its string forms, screen= absent stays absent ────────────
    opts = window("at=50%")
    H.eq(opts.at, "50%", "a percentage stays a string")
    H.eq(opts.screen, nil, "no screen= passes no screen")

    -- ── a screen= that cannot be a display index is dropped, not formatted ─
    -- `player.args` formats the number with `%d`: `inf` and `nan` would become
    -- `--screen=-9223372036854775808`, and `-1` is no display at all.
    for _, bad in ipairs({ "-1", "inf", "nan", "abc" }) do
      opts = window("at=7 screen=" .. bad)
      H.eq(opts.screen, nil, "screen=" .. bad .. " is not passed on")
      H.eq(opts.at, 7, "...and does not take at= down with it")
    end

    -- A fractional display is the whole number below it, like every other numeric key.
    opts = window("screen=1.9")
    H.eq(opts.screen, 1, "screen=1.9 is display 1")

    -- ── the shared body takes the same options without the command line ────
    calls = {}
    usrcmds.run("window", "/media-spec/clip.mp4", { at = 9, screen = 3 })
    H.eq(#calls, 1, "M.run('window') opens one window")
    H.eq(calls[1].opts.at, 9, "M.run forwards at")
    H.eq(calls[1].opts.screen, 3, "M.run forwards screen")
  end)

  media.play_window = orig
  pcall(vim.api.nvim_del_user_command, "Media")
  if not run_ok then error(err, 0) end
end
