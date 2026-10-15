-- Bounding the render cache: the rule (pure), then the real thing on a throw-away directory.
--
-- What has to hold: the oldest files go first, by age and by total size; only the files this
-- cache owns are touched (a stranger in the directory stays); a `.tmp-<pid>` leftover goes only
-- when it is old; nothing is touched while a render is running; `nil`/`0` means unlimited.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local cache = require("media.core.cache")
  local config = require("media.config")
  local uv = vim.uv or vim.loop

  local DAY = 86400
  local NOW = 1800000000

  ---@param name string
  ---@param size integer
  ---@param age_days number
  ---@param tmp? boolean
  ---@return Media.Cache.File
  local function file(name, size, age_days, tmp)
    return {
      path = "/c/" .. name,
      name = name,
      size = size,
      mtime = NOW - math.floor(age_days * DAY),
      tmp = tmp == true,
    }
  end

  ---@param list Media.Cache.File[]
  ---@return string[]
  local function names(list)
    local out = {}
    for _, f in ipairs(list) do
      out[#out + 1] = f.name
    end
    table.sort(out)
    return out
  end

  local function same(a, b, msg)
    H.eq(vim.inspect(a), vim.inspect(b), msg)
  end

  local MB = 1048576

  -- ── the rule ───────────────────────────────────────────────────────────
  do
    local files = {
      file("old.png", 10, 40),
      file("new.png", 10, 1),
      file("mid.wav", 10, 20),
    }
    same(
      names(cache.plan_prune(files, NOW, { max_age_days = 30 })),
      { "old.png" },
      "age: only older than the limit"
    )
    same(names(cache.plan_prune(files, NOW, {})), {}, "no limit, nothing goes")
    same(
      names(cache.plan_prune(files, NOW, { max_age_days = 100 })),
      {},
      "all younger than the limit"
    )

    -- size: oldest first, and no more than needed
    local big = {
      file("a.wav", 4 * MB, 30),
      file("b.wav", 4 * MB, 20),
      file("c.png", 4 * MB, 10),
      file("d.png", 4 * MB, 1),
    }
    same(
      names(cache.plan_prune(big, NOW, { max_mb = 9 })),
      { "a.wav", "b.wav" },
      "size: the two oldest go to get under 9 MB"
    )
    same(
      names(cache.plan_prune(big, NOW, { max_mb = 12 })),
      { "a.wav" },
      "size: one is enough for 12 MB"
    )
    same(names(cache.plan_prune(big, NOW, { max_mb = 16 })), {}, "exactly at the limit is fine")
    local both = cache.plan_prune(big, NOW, { max_mb = 9, max_age_days = 25 })
    same(names(both), { "a.wav", "b.wav" }, "age first, then size over what is left")
    local aged = cache.plan_prune(big, NOW, { max_mb = 5, max_age_days = 25 })
    same(names(aged), { "a.wav", "b.wav", "c.png" }, "size counts only what the age rule kept")

    -- tmp leftovers: old ones go, young ones may belong to another Neovim
    local tmps = {
      file("x.png.tmp-123", 1, 0.5, true),
      file("y.png.tmp-456", 1, 0.01, true),
    }
    same(
      names(cache.plan_prune(tmps, NOW, { max_mb = 1 })),
      { "x.png.tmp-123" },
      "an old leftover goes, a fresh one stays"
    )

    -- a render in flight is never judged
    local busy = { ["/c/live.png"] = true, ["/c/live2.png"] = true }
    local inflight_files = {
      file("live.png", 10, 90),
      file("live2.png.tmp-9", 1, 5, true),
      file("live3.tmp-9.png", 1, 5, true), -- the form `tmp_for` really writes: <base>.tmp-<pid>.<ext>
      file("dead.png", 10, 90),
    }
    busy["/c/live3.png"] = true
    same(
      names(cache.plan_prune(inflight_files, NOW, { max_age_days = 30 }, busy)),
      { "dead.png" },
      "busy outputs and their tmp files stay"
    )
  end

  -- ── limits from the config ─────────────────────────────────────────────
  do
    config.setup({ cache = { max_age_days = 7, max_mb = 50 } })
    same(cache.limits(), { max_age_days = 7, max_mb = 50 }, "limits are read from the config")
    config.setup({ cache = { max_age_days = 0, max_mb = false } })
    same(cache.limits(), {}, "0 and non-numbers mean unlimited")
    config.setup({})
    same(cache.limits(), { max_age_days = 30, max_mb = 2048 }, "generous defaults")
  end

  -- ── on a real directory ───────────────────────────────────────────────
  --- A name the cache itself would write: a sha256 key (64 hex digits), then the rest.
  ---@param rest string
  ---@return string
  local function K(rest)
    return ("0"):rep(64) .. "-" .. rest
  end
  local dir = vim.fn.tempname() .. "-media-prune"
  vim.fn.mkdir(dir, "p")
  config.setup({ cache = { dir = dir } })

  ---@param name string
  ---@param size integer
  ---@param age_days number
  local function put(name, size, age_days)
    local f = assert(io.open(dir .. "/" .. name, "wb"))
    f:write(("x"):rep(size))
    f:close()
    local t = os.time() - math.floor(age_days * DAY)
    assert(uv.fs_utime(dir .. "/" .. name, t, t))
  end

  ---@param opts table|nil
  ---@return Media.Cache.PruneResult
  local function prune(opts)
    local result
    cache.prune(opts, function(r)
      result = r
    end)
    vim.wait(3000, function()
      return result ~= nil
    end, 5)
    H.ok(result ~= nil, "prune called back")
    return result
  end

  ---@return string[]
  local function listing()
    local out = {}
    for name in vim.fs.dir(dir) do
      out[#out + 1] = name
    end
    table.sort(out)
    return out
  end

  put(K("old.png"), 100, 60)
  put(K("fresh.png"), 100, 1)
  put(K("old.json"), 100, 45)
  put(K("old.wav"), 100, 90)
  put("stranger.txt", 100, 400)
  put("notes", 100, 400)
  -- the user's own files in a custom cache.dir: right extension, ancient, but not named after a key
  put("user.json", 100, 400)
  put("photo.png", 100, 400)
  put(K("stale.png.tmp-4242"), 10, 2)
  put(K("young.png.tmp-4243"), 10, 0)
  vim.fn.mkdir(dir .. "/subdir", "p")

  local unlimited = prune({ limits = {} })
  H.eq(unlimited.skipped, "unlimited", "no limits: nothing scanned")
  H.eq(#listing(), 11, "and nothing removed")

  local res = prune({ limits = { max_age_days = 30 } })
  H.eq(res.removed, 4, "old png/json/wav and the stale tmp file")
  same(listing(), {
    K("fresh.png"),
    K("young.png.tmp-4243"),
    "notes",
    "photo.png",
    "stranger.txt",
    "subdir",
    "user.json",
  }, "strangers, directories and fresh files stay")
  H.eq(res.kept, 1, "one cache file kept")
  H.eq(res.bytes, 100, "its size")
  H.eq(res.freed, 310, "bytes freed")

  -- by size
  put(K("a.png"), 1000, 10)
  put(K("b.png"), 1000, 5)
  put(K("c.png"), 1000, 2)
  local sized = prune({ limits = { max_mb = 2000 / MB } })
  H.eq(sized.removed, 2, "two of the three big ones go to get under 2000 bytes (fresh.png is 100)")
  same(listing(), {
    K("c.png"),
    K("fresh.png"),
    K("young.png.tmp-4243"),
    "notes",
    "photo.png",
    "stranger.txt",
    "subdir",
    "user.json",
  }, "the oldest went first")

  -- not while a render runs
  local finish
  local out = vim.fn.tempname() .. "-busy.png"
  cache.ensure(out, function(done)
    finish = done
  end, function() end)
  H.ok(finish ~= nil, "a render is running")
  put(K("zzz.png"), 100, 400)
  local busy = prune({ limits = { max_age_days = 30 } })
  H.eq(busy.skipped, "busy", "prune waits for the render queue to be empty")
  H.ok(vim.uv.fs_stat(dir .. "/" .. K("zzz.png")) ~= nil, "and removes nothing")
  finish(nil)
  vim.wait(500, function()
    return (select(1, cache.load())) == 0
  end, 5)
  local after = prune({ limits = { max_age_days = 30 } })
  H.eq(after.removed, 1, "once idle, the old file goes")

  -- health numbers
  local count, bytes = cache.stats()
  H.eq(count, 2, "stats counts cache files only (c.png, fresh.png)")
  H.eq(bytes, 1100, "and their bytes")

  -- a directory that does not exist yet is not an error
  config.setup({ cache = { dir = dir .. "/nope/deeper" } })
  local missing = prune({ limits = { max_age_days = 1 } })
  H.eq(missing.removed, 0, "an empty cache directory prunes to nothing")

  config.setup({})
  vim.fn.delete(dir, "rf")
end
