-- media.core.bin: the explicit-config-always-wins rule, the per-name cache
-- and its reset. Uses fabricated binary names throughout so a real (or
-- missing) ffmpeg/mpv install on the machine running this suite cannot change
-- the outcome — the one exception is the `available()` check at the end,
-- which touches the real "ffmpeg"/"ffprobe" cache entries and resets them
-- back to "unlooked-up" afterwards so `smoke_spec`'s own `media.available()`
-- call still does a real, uncached lookup.
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

  -- ── the answer is cached: a config change alone does not take effect ──
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/other.exe" } })
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/does-not-exist.exe",
    "the first lookup is cached; a later config change is not seen until reset"
  )

  -- ── reset(name) clears exactly that one entry ──────────────────────────
  bin.reset("mpv")
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/other.exe",
    "reset(name) makes the new config visible"
  )

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

  -- ── reset() with no argument clears every cached name ──────────────────
  bin.reset()
  config.setup({ bin = { [missing] = "E:/__media_bin_spec__/now-configured.exe" } })
  H.eq(
    bin.find(missing),
    "E:/__media_bin_spec__/now-configured.exe",
    "a bare reset() clears the whole cache, not just the last-looked-up name"
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
