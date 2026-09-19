-- media.core.bin: the explicit-config-always-wins rule, the per-name cache
-- keyed on (name, configured value), and its reset. Uses fabricated binary
-- names throughout so a real (or missing) ffmpeg/mpv install on the machine
-- running this suite cannot change the outcome — the one exception is the
-- `available()` check at the end, which touches the real "ffmpeg"/"ffprobe"
-- cache entries and resets them back to "unlooked-up" afterwards so
-- `smoke_spec`'s own `media.available()` call still does a real, uncached
-- lookup.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local bin = require("media.core.bin")
  local config = require("media.config")

  -- ── an explicit config path is honoured even though it does not exist ──
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/does-not-exist.exe" } })
  bin.reset("mpv")
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/does-not-exist.exe",
    "an explicit config path wins over PATH/well-known lookups, existing or not"
  )

  -- ── a config change is picked up on the very next find(), no reset() ───
  -- The cache key is (name, config.get().bin[name]): a different configured
  -- value is a cache miss on its own, so a stale answer can no longer
  -- outlive the `setup()` call that changed it.
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/other.exe" } })
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/other.exe",
    "a config change invalidates the cache by itself; find() sees it immediately"
  )

  -- ── an unchanged config is still cached: repeating the same setup() does
  --    not re-derive the answer, it returns the same cached entry ─────────
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/other.exe" } })
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/other.exe",
    "an identical config value is still a cache hit"
  )

  -- ── reset(name) still works, for what a config diff cannot see (PATH or
  --    an install changing under an unchanged config) ─────────────────────
  bin.reset("mpv")
  H.eq(bin.find("mpv"), "E:/__media_bin_spec__/other.exe", "reset(name) re-derives the same answer")

  -- ── a name that is neither configured, on PATH, nor in a well-known
  --    install directory resolves to nil, and stays nil on a second ask ──
  config.setup({})
  local missing = "__media_bin_spec_missing__"
  H.eq(bin.find(missing), nil, "nothing found for a name that exists nowhere")
  H.eq(
    bin.find(missing),
    nil,
    "the negative result is cached too, not re-derived as something else"
  )

  -- ── configuring a previously-missing name takes effect immediately,
  --    no reset() needed — this is the case PERF-46 was about: a user who
  --    configures `bin.ffmpeg` after an earlier failed lookup must not keep
  --    getting "not found" for the rest of the session ───────────────────
  config.setup({ bin = { [missing] = "E:/__media_bin_spec__/now-configured.exe" } })
  H.eq(
    bin.find(missing),
    "E:/__media_bin_spec__/now-configured.exe",
    "configuring a name that previously resolved to nil is seen without reset()"
  )

  -- ── reset() with no argument still clears every cached name ────────────
  bin.reset()
  H.eq(
    bin.find(missing),
    "E:/__media_bin_spec__/now-configured.exe",
    "a bare reset() re-derives the same answer for every name"
  )

  -- ── available(): true means both binaries resolved to *something*,
  --    not that either file actually exists — the same "honour the config
  --    as given" rule M.find documents ────────────────────────────────────
  bin.reset("ffmpeg")
  bin.reset("ffprobe")
  config.setup({
    bin = {
      ffmpeg = "E:/__media_bin_spec__/ffmpeg-fake.exe",
      ffprobe = "E:/__media_bin_spec__/ffprobe-fake.exe",
    },
  })
  H.eq(bin.available(), true, "available() trusts an explicit config path without stat'ing it")

  -- Leave no trace for later specs/consumers: real, uncached lookups again.
  bin.reset("ffmpeg")
  bin.reset("ffprobe")
  bin.reset(missing)
  config.setup({})
end
