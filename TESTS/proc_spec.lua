-- Stopping a spawned process.
--
-- The measurement behind this file (2026-09-08): an mpv started with
-- `vim.system` survived `proc:kill(15)`, `proc:kill("sigterm")`, `proc:kill(9)`
-- and `uv.kill(pid, "sigkill")` — all four reporting success — because Windows
-- resolved the bare `mpv` to `mpv.COM`, a console wrapper whose child is the
-- actual player. Only `taskkill /T /F` stopped it.
--
-- What is assertable without spawning anything is the argv, and it is exactly
-- where the bug was: without `/T` this reaches the wrapper and not the player.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local proc = require("media.core.proc")

  local argv = proc.taskkill_argv(4321)
  H.eq(argv[1], "taskkill", "the tool")
  H.before(argv, "/PID", "/T", "the pid is named before the flags that act on it")
  H.eq(argv[H.index_of(argv, "/PID") + 1], "4321", "the pid is a string in the argv")

  -- `/T` is the whole fix: it takes the children with it. A stop without it
  -- kills the `mpv.COM` wrapper and leaves the player it started running,
  -- reparented and unreachable — which is the failure this exists for.
  H.ok(H.index_of(argv, "/T"), "the tree flag is there")
  -- `/F` because a player asked politely to close does not always.
  H.ok(H.index_of(argv, "/F"), "the force flag is there")

  H.eq(type(proc.needs_tree_kill()), "boolean", "the platform question is answerable")

  -- Teardown paths must never raise: this runs from a closing hover and from
  -- `VimLeavePre`, where an error is both useless and badly timed.
  local ok = pcall(proc.stop, nil)
  H.ok(ok, "a nil process is not an error")
  ok = pcall(proc.stop, "not a process")
  H.ok(ok, "nor is something that is not a process at all")
  ok = pcall(proc.stop, {})
  H.ok(ok, "nor a table without a pid or a kill")
end
