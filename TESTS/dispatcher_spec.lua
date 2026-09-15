-- media.core.dispatcher: join/dedup, cancel-only-when-last-waiter-leaves, the
-- empty-string-argument fallback and the cache hit/miss branches. This is the
-- module a 2026-09-14 review found a real race condition in (two identical
-- `:Media transcribe` calls spawning two `whisper-cli` processes racing on the
-- same output file) — the failure mode these specs exist to catch again.
--
-- `media.core.normalize`, `media.core.resolver` and `media.core.cache` are
-- swapped for stub tables for the duration of this spec so the pipeline can
-- be driven deterministically, without ffmpeg or whisper-cli installed. The
-- real modules are restored in every exit path (`pcall` below) — a later spec
-- (`normalize_args_spec`, `resolver_spec`, `cache_key_spec`) must see the real
-- thing regardless of whether an assertion here fails.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local dispatcher = require("media.core.dispatcher")
  local config = require("media.config")

  -- Force-load the real modules before they get replaced, so the reference
  -- below is the genuine implementation, not a stub from an earlier spec.
  local real_normalize = require("media.core.normalize")
  local real_resolver = require("media.core.resolver")
  local real_cache = require("media.core.cache")

  local normalize_stub = {
    normalize = function()
      error("normalize stub not configured for this phase")
    end,
  }
  local resolver_stub = {
    resolve = function()
      error("resolver stub not configured for this phase")
    end,
  }
  local cache_stub = {
    file = function()
      error("cache stub not configured for this phase")
    end,
  }
  package.loaded["media.core.normalize"] = normalize_stub
  package.loaded["media.core.resolver"] = resolver_stub
  package.loaded["media.core.cache"] = cache_stub

  local function restore()
    package.loaded["media.core.normalize"] = real_normalize
    package.loaded["media.core.resolver"] = real_resolver
    package.loaded["media.core.cache"] = real_cache
    config.setup({})
  end

  local ok, err = pcall(function()
    -- ── a second identical call joins the first instead of starting its
    --    own pipeline ──────────────────────────────────────────────────
    do
      local path = "/tmp/__dispatcher_spec_dedup.mkv"
      local normalize_calls = 0
      local pending_cb = nil
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      normalize_stub.normalize = function(_, callback)
        normalize_calls = normalize_calls + 1
        pending_cb = callback
        return { cancel = function() end }
      end
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      resolver_stub.resolve = function()
        local fake_engine = {
          id = "fake",
          transcribe = function(_, _, callback)
            callback({ engine = "fake", segments = {}, text = "joined result" }, nil)
            return { cancel = function() end }
          end,
        }
        return fake_engine, nil
      end

      local first, second
      dispatcher.transcribe(path, { cache = false }, function(t, e)
        first = { t, e }
      end)
      dispatcher.transcribe(path, { cache = false }, function(t, e)
        second = { t, e }
      end)

      H.eq(normalize_calls, 1, "the second call did not start its own normalize pass")
      H.ok(pending_cb ~= nil, "the pipeline is waiting on normalize")

      -- Completing the shared pipeline must fan out to both waiters.
      pending_cb("/tmp/fake.wav", nil)
      H.ok(first ~= nil, "the first caller got a result")
      H.ok(second ~= nil, "the second caller got a result too, from the same run")
      H.eq(first[1].text, "joined result", "same transcript object reaches both")
      H.eq(second[1].text, "joined result", "same transcript object reaches both")
    end

    -- ── cancelling one joined caller must not cancel the run for the
    --    other; the underlying job is only stopped once every waiter has
    --    given up — and once that happens, the slot must be free again for
    --    a later call, not stuck joining a job that will never call back
    --    (a real regression this spec caught: normalize's/the engine's own
    --    `cancel()` permanently suppresses their callback, which used to be
    --    the *only* thing that cleared `inflight`) ────────────────────────
    do
      local path = "/tmp/__dispatcher_spec_cancel.mkv"
      local underlying_cancelled = false
      local normalize_starts = 0
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      normalize_stub.normalize = function()
        normalize_starts = normalize_starts + 1
        return {
          cancel = function()
            underlying_cancelled = true
          end,
        }
      end
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      resolver_stub.resolve = function()
        error("must not resolve an engine while normalize never called back")
      end

      local handle1 = dispatcher.transcribe(path, { cache = false }, function() end)
      local handle2 = dispatcher.transcribe(path, { cache = false }, function() end)
      H.eq(normalize_starts, 1, "the second call joined instead of starting its own pass")

      handle2.cancel()
      H.eq(underlying_cancelled, false, "one of two waiters leaving keeps the run alive")

      handle1.cancel()
      H.eq(underlying_cancelled, true, "the last waiter leaving stops the underlying run")

      -- normalize's own `cancel()` (the stub above) marks itself cancelled
      -- and never calls back — exactly the case that used to leak the
      -- `inflight` entry forever. A fresh call for the same key must start
      -- a new pass, not join the abandoned one and hang silently.
      dispatcher.transcribe(path, { cache = false }, function() end)
      H.eq(normalize_starts, 2, "a call after full cancellation starts fresh, not joins a dead job")
    end

    -- ── an empty-string opts field falls back to the configured default
    --    rather than being treated as a real (falsy-looking but truthy)
    --    value — `nonempty_or`'s reason to exist ─────────────────────────
    do
      config.setup({
        transcribe = { engine = "cfg-engine", lang = "cfg-lang", task = "translate", cache = false },
      })
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      normalize_stub.normalize = function(_, callback)
        callback("/tmp/fake.wav", nil)
        return { cancel = function() end }
      end

      local resolved_with, transcribe_opts
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      resolver_stub.resolve = function(requested)
        resolved_with = requested
        local fake_engine = {
          id = "fake",
          transcribe = function(_, opts, callback)
            transcribe_opts = opts
            callback({ engine = "fake", segments = {}, text = "ok" }, nil)
            return { cancel = function() end }
          end,
        }
        return fake_engine, nil
      end

      dispatcher.transcribe(
        "/tmp/__dispatcher_spec_empty_opts.mkv",
        { engine = "", lang = "", cache = false },
        function() end
      )
      H.eq(resolved_with, "cfg-engine", "an empty-string engine falls back to the configured one")
      H.eq(transcribe_opts.lang, "cfg-lang", "an empty-string lang falls back too")
      H.eq(transcribe_opts.task, "translate", "an omitted task falls back to the configured one")

      dispatcher.transcribe(
        "/tmp/__dispatcher_spec_explicit_opts.mkv",
        { engine = "explicit", lang = "explicit-lang", task = "translate", cache = false },
        function() end
      )
      H.eq(resolved_with, "explicit", "a real value is never overridden by the default")
      H.eq(transcribe_opts.lang, "explicit-lang", "same for lang")
      H.eq(transcribe_opts.task, "translate", "same for task")
    end

    -- ── a cache hit skips normalize/resolve/transcribe entirely ─────────
    do
      config.setup({})
      -- `vim.fn.tempname()`, not the `os` stdlib equivalent (`SEC-47`) —
      -- same reason `media.engines.whisper_cpp` uses it for its own scratch
      -- output.
      local cache_path = vim.fn.tempname()
      local fd = assert(io.open(cache_path, "w"))
      fd:write(vim.json.encode({ engine = "cached", segments = {}, text = "from cache" }))
      fd:close()

      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      cache_stub.file = function()
        return cache_path, nil
      end
      local normalize_called = false
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      normalize_stub.normalize = function(_, callback)
        normalize_called = true
        callback(nil, "must not run on a cache hit")
        return { cancel = function() end }
      end

      local got
      dispatcher.transcribe("/tmp/__dispatcher_spec_cache_hit.mkv", {}, function(t, e)
        got = { t, e }
      end)
      vim.wait(500, function()
        return got ~= nil
      end, 5)

      os.remove(cache_path)
      H.ok(got ~= nil, "the cache-hit callback fired")
      H.eq(normalize_called, false, "a cache hit never touches normalize")
      H.eq(got[1] and got[1].text, "from cache", "the cached transcript is what came back")
    end

    -- ── a cache miss runs the pipeline and writes the result back ───────
    do
      -- `vim.fn.tempname()` (`SEC-47`) hands back a path it has not created
      -- (unlike the `os` stdlib equivalent) — exactly "does not exist yet",
      -- which is what makes this a miss.
      local cache_path = vim.fn.tempname()

      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      cache_stub.file = function()
        return cache_path, nil
      end
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      normalize_stub.normalize = function(_, callback)
        callback("/tmp/fake.wav", nil)
        return { cancel = function() end }
      end
      -- Reconfiguring the test double for this phase, not a real duplicate.
      ---@diagnostic disable-next-line: duplicate-set-field
      resolver_stub.resolve = function()
        local fake_engine = {
          id = "fake",
          transcribe = function(_, _, callback)
            callback({ engine = "fake", segments = {}, text = "fresh result" }, nil)
            return { cancel = function() end }
          end,
        }
        return fake_engine, nil
      end

      local got
      dispatcher.transcribe("/tmp/__dispatcher_spec_cache_miss.mkv", {}, function(t)
        got = t
      end)
      vim.wait(500, function()
        return got ~= nil
      end, 5)

      H.ok(got ~= nil, "the cache-miss callback fired")
      H.eq(got.text, "fresh result", "the freshly produced transcript came back")

      -- The cache write is async and fire-and-forget (does not gate the
      -- callback above), so give it a moment to land before reading it back.
      vim.wait(500, function()
        return vim.uv.fs_stat(cache_path) ~= nil
      end, 5)
      local fd = io.open(cache_path, "r")
      H.ok(fd ~= nil, "the fresh result was written to the cache path")
      if fd then
        local content = fd:read("*a")
        fd:close()
        H.match(content, "fresh result", "the written cache file holds the new transcript")
        os.remove(cache_path)
      end
    end
  end)

  restore()
  if not ok then error(err, 0) end
end
