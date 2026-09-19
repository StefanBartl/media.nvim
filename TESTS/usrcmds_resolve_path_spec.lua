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
end
