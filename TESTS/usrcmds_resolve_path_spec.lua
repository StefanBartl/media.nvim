-- media.bindings.usrcmds.resolve_path(): what a `:Media <verb> <path>`
-- argument goes through before anything touches the filesystem (SEC-34).
-- `vim.fn.expand()` is Vim's filename expansion: a backtick span in it is a
-- command substitution over `&shell`, and `%`/`#`/`<cfile>` are specials --
-- all live risks on exactly the string a user typed on the command line.
-- Only `~` and environment variables are wanted here.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local usrcmds = require("media.bindings.usrcmds")

  -- ── a backtick span is left as literal text, never run as a shell command ──
  local raw = "`echo SEC_34_SHOULD_NOT_RUN`"
  H.eq(
    usrcmds.resolve_path(raw),
    raw,
    "no `~`/env pattern in it, so it passes through completely unchanged -- never a command substitution"
  )

  -- ── `~` and `$VAR` still expand -- the one thing this is actually for ──
  vim.env.MEDIA_USRCMDS_SPEC_VAR = "/media-spec-value"
  H.eq(
    usrcmds.resolve_path("$MEDIA_USRCMDS_SPEC_VAR/clip.mp4"),
    "/media-spec-value/clip.mp4",
    "an environment variable in the argument still expands"
  )
  vim.env.MEDIA_USRCMDS_SPEC_VAR = nil

  -- ── an empty argument falls back to the cursor/buffer target, not "" ───
  H.eq(
    usrcmds.resolve_path(""),
    require("media.bindings.keymaps").target(),
    "no explicit path given falls back the same way a bare `:Media <verb>` does"
  )

  -- ── bare `:Media`: probe with a target, dashboard without one ──────────
  -- Both registrations (composer route and the no-lib.nvim fallback) go
  -- through `M.bare`; the fallback is exercised for real below, the composer
  -- route is one line over the same function.
  local keymaps = require("media.bindings.keymaps")
  local dashboard = require("media.hub.dashboard")
  local orig = { target = keymaps.target, open = dashboard.open, run = usrcmds.run }
  local runs, opens = {}, 0
  keymaps.target = function()
    return nil
  end
  dashboard.open = function()
    opens = opens + 1
  end
  usrcmds.run = function(action, path)
    runs[#runs + 1] = { action, path }
  end

  usrcmds.bare(nil)
  H.eq(opens, 1, "bare :Media with no path and no file under the cursor opens the dashboard")
  H.eq(#runs, 0, "...and does not probe anything")

  usrcmds.bare("/media-spec/clip.mp4")
  H.eq(opens, 1, "an explicit path does not open the dashboard")
  H.eq_list(runs[1], { "probe", "/media-spec/clip.mp4" }, "an explicit path stays the probe")

  keymaps.target = function()
    return "/media-spec/under-cursor.mp4"
  end
  usrcmds.bare(nil)
  H.eq(opens, 1, "a file under the cursor does not open the dashboard")
  H.eq_list(
    runs[2],
    { "probe", "/media-spec/under-cursor.mp4" },
    "a file under the cursor stays the probe"
  )

  -- the fallback command: no argument at all is the bare form, any argument is not
  usrcmds.register_fallback()
  keymaps.target = function()
    return nil
  end
  vim.cmd("Media")
  H.eq(opens, 2, "fallback :Media with no argument and no target opens the dashboard")
  vim.cmd("Media probe /media-spec/other.mp4")
  H.eq_list(
    runs[3],
    { "probe", "/media-spec/other.mp4" },
    "fallback :Media probe <path> is unchanged"
  )

  keymaps.target, dashboard.open, usrcmds.run = orig.target, orig.open, orig.run
  pcall(vim.api.nvim_del_user_command, "Media")
end
