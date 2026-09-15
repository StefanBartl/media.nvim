-- media.config: the no-setup() snapshot and the merge. Must run before any
-- other spec touches `media.config` — the snapshot-identity assertion below
-- only means anything the first time `M.get()` is ever called in this
-- process, before `setup()` has run. `TESTS/run.lua` keeps this file first
-- in the spec list for exactly that reason.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local config = require("media.config")
  local DEFAULTS = require("media.config.DEFAULTS")

  -- ── before setup(): the defaults, usable on their own (`NEW-24`) ───────
  local cfg1 = config.get()
  H.eq(cfg1.frame.at, DEFAULTS.frame.at, "no setup() means the plugin's own defaults")

  -- ── the no-setup() snapshot is built once and reused, not re-copied on
  --    every call — every real caller only reads it, so this is safe, and
  --    it is what keeps a hover-triggered `core.probe`/`core.frame` call
  --    from re-walking the whole config tree on every cursor move ────────
  local cfg2 = config.get()
  H.eq(cfg1, cfg2, "two no-setup() calls return the identical table")

  -- ── setup() merges over a fresh copy of DEFAULTS, and M.get() reflects
  --    it from then on ────────────────────────────────────────────────────
  config.setup({ frame = { width = 321 } })
  local cfg3 = config.get()
  H.eq(cfg3.frame.width, 321, "an explicit option reaches M.get()")
  H.eq(cfg3.frame.at, DEFAULTS.frame.at, "an untouched key keeps its default")
  H.ok(cfg3 ~= cfg1, "setup() replaces the snapshot, not mutates it")

  -- ── a second setup() call fully replaces the first, not merges onto it ──
  config.setup({ timeout_ms = 999 })
  local cfg4 = config.get()
  H.eq(cfg4.timeout_ms, 999, "the new setup() call's own option")
  H.eq(cfg4.frame.width, DEFAULTS.frame.width, "the previous setup() call's option is gone")

  -- Leave config at the defaults for whichever spec runs next — this module
  -- has no reset(); a bare setup({}) is the equivalent every other spec that
  -- calls setup() already uses for the same cleanup.
  config.setup({})
end
