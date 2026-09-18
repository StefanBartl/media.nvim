-- media.health: `M.check()` must never raise, on a machine with none of its
-- external toolchain — which is exactly the machine CI runs on (no ffmpeg,
-- no ffprobe, no mpv, no whisper-cli, no configured model).
--
-- Every one of the four patterns this campaign keeps finding in a `health.lua`
-- is the same shape: report "X is missing" and then call into X anyway right
-- after, crashing instead of degrading. Reading the source rules that out
-- here, but nothing in the suite ever actually *called* `M.check()` before
-- this — `smoke_spec` only asserts the module loads, never runs it. A `pcall`
-- guard that looks right and a code path that has never executed once are two
-- different facts.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local health = require("media.health")

  -- Real `vim.health`, real (missing) binaries, real filesystem for the cache
  -- probe — nothing here is stubbed, because a stub would hide exactly the
  -- crash this spec exists to catch.
  local ok, err = pcall(health.check)
  H.ok(ok, ("media.health.check() must not raise: %s"):format(tostring(err)))

  -- Twice: `M.check()` holds no state of its own, so a second run on the same
  -- session must behave identically to the first rather than tripping over
  -- anything the first run left behind (a cached bin lookup, a created cache
  -- directory).
  local ok2, err2 = pcall(health.check)
  H.ok(ok2, ("a second checkhealth run must not raise either: %s"):format(tostring(err2)))
end
