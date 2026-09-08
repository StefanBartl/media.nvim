---@module 'media.core.proc'
---@brief Stopping a spawned process — which on Windows is not `kill`.
---@description
--- **The measurement this module exists for** (2026-09-08, this machine): an
--- mpv started with `vim.system({ "mpv", … })` survived `proc:kill(15)`,
--- `proc:kill("sigterm")`, `proc:kill(9)` *and* `uv.kill(pid, "sigkill")`.
--- Every one of them returned success. The sound kept playing until the
--- process was killed by hand in the task manager.
---
--- The reason is `PATHEXT`. Windows resolves a bare `mpv` to **`mpv.COM`**
--- before `mpv.exe`, because `.COM` comes first in that list — and `mpv.com`
--- is a console wrapper that spawns the real `mpv.exe` as a *child* and relays
--- to it. So the pid `vim.system` hands back is the wrapper's. Killing it
--- leaves the player running, reparented and unreachable:
---
--- ```
--- ProcessId : 70808  Name : mpv.com   <- what vim.system spawned and kills
--- ProcessId : 58932  Name : mpv.exe   <- what is actually making the sound
--- ParentProcessId : 70808
--- ```
---
--- This is not an mpv quirk. Every `.com`/`.cmd`/`.bat` launcher on PATH has
--- the same shape, and so does a scoop shim — which is how most of this
--- machine's tooling is installed. Anything this plugin spawns and later has
--- to stop has to stop the *tree*.
---
--- `taskkill /T /F` does stop it (measured: running 1 -> 0 where every signal
--- above left it at 1). On POSIX there is no wrapper and no problem, and
--- `proc:kill` is both correct and cheaper.

local M = {}

--- The argv that stops the tree rooted at `pid` on Windows.
---
--- Pure and public so the flags are assertable without spawning anything.
--- `/T` is the whole point — it takes the children with it — and `/F` is what
--- makes it work on a process that is not cooperating with a close request.
---@param pid integer
---@return string[]
function M.taskkill_argv(pid)
  return { "taskkill", "/PID", tostring(pid), "/T", "/F" }
end

--- Whether this platform needs the tree treatment.
---@return boolean
function M.needs_tree_kill()
  return vim.fn.has("win32") == 1
end

--- Stop `proc` and everything it started.
---
--- Never raises: this runs from teardown paths — a closing hover, `VimLeavePre`
--- — where an error would be both useless and badly timed. A process that is
--- already gone is not an error either; `taskkill` reports it and nobody here
--- is listening.
---@param proc vim.SystemObj|nil
---@return nil
function M.stop(proc)
  if type(proc) ~= "table" then return end

  if M.needs_tree_kill() and type(proc.pid) == "number" then
    -- **Awaited, and `proc:kill` is deliberately not called alongside it.**
    -- The first version of this function did both, taskkill unawaited and a
    -- signal straight after — and mpv survived that too, for a reason worth
    -- writing down: the signal reaches the `mpv.COM` wrapper first and kills
    -- it, the real `mpv.exe` is reparented away from the tree, and the
    -- `taskkill /T` that arrives a moment later walks a tree that no longer
    -- contains the process it was sent for. Racing your own cleanup is worse
    -- than not cleaning up: it turns a stoppable child into an orphan.
    --
    -- The wait is bounded and short. On `VimLeavePre` it is the last thing
    -- between a reader and silence, and a second is a price worth paying
    -- there — the alternative measured out as sound that never stops.
    pcall(function()
      vim.system(M.taskkill_argv(proc.pid), {}):wait(2000)
    end)
    return
  end

  pcall(function()
    proc:kill(15)
  end)
end

return M
