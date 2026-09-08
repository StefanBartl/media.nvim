-- The cache key.
--
-- A cache that never expires is only safe if two renderings that differ in any
-- way get different names. This is the spec that says so — a collision here
-- serves the wrong picture for as long as the cache lives, which is forever.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local cache = require("media.core.cache")

  local base = cache.key("frame", "/tmp/clip.mp4", 1700000000, { "27.5", 800, "video" })
  H.eq(#base, 64, "a sha256 in hex")
  H.eq(
    base,
    cache.key("frame", "/tmp/clip.mp4", 1700000000, { "27.5", 800, "video" }),
    "the same inputs give the same name — that is what makes a hit a hit"
  )

  ---@param what string
  ---@param other string
  local function differs(what, other)
    H.ok(base ~= other, what .. " changes the key")
  end

  differs("the kind", cache.key("sheet", "/tmp/clip.mp4", 1700000000, { "27.5", 800, "video" }))
  differs("the path", cache.key("frame", "/tmp/other.mp4", 1700000000, { "27.5", 800, "video" }))
  -- The mtime is the whole invalidation strategy: an edited file has a
  -- different one, so it misses and renders again, and nothing has to decide
  -- when a kept entry went stale.
  differs("the mtime", cache.key("frame", "/tmp/clip.mp4", 1700000001, { "27.5", 800, "video" }))
  differs("the offset", cache.key("frame", "/tmp/clip.mp4", 1700000000, { "27.6", 800, "video" }))
  differs("the width", cache.key("frame", "/tmp/clip.mp4", 1700000000, { "27.5", 801, "video" }))
  differs(
    "the source stream",
    cache.key("frame", "/tmp/clip.mp4", 1700000000, { "27.5", 800, "cover" })
  )

  -- Joining the fields with a separator rather than concatenating them: without
  -- one, ("a", 11) and ("a1", 1) are the same string.
  H.ok(
    cache.key("frame", "/tmp/a", 1, { 11 }) ~= cache.key("frame", "/tmp/a", 1, { 1, 1 }),
    "field boundaries survive into the key"
  )
end
