-- media.core.cache's render queue: the concurrency bound, the priority order,
-- and giving up on a render that has not started.
--
-- The `render` function is a stub that answers when the spec tells it to, so
-- these are assertions about scheduling rather than about ffmpeg. What they
-- pin is what a measurement found on 2026-09-17: holding a paging key down
-- put 30 concurrent processes on the machine, 60 with prefetching, and a
-- playback window queued behind them arrived at 1111 ms against a 1000 ms
-- budget.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local cache = require("media.core.cache")
  local config = require("media.config")

  -- Every `out` below is a path that does not exist, so `ensure` never takes
  -- its cache-hit branch. `tempname` hands back a path it has not created.
  local counter = 0
  ---@return string
  local function fresh()
    counter = counter + 1
    return ("%s-queue-%d.png"):format(vim.fn.tempname(), counter)
  end

  ---@return integer
  local function running()
    return (select(1, cache.load()))
  end

  ---@return integer
  local function waiting()
    return (select(2, cache.load()))
  end

  local ok, err = pcall(function()
    config.setup({ render_concurrency = 3 })

    -- ── the bound holds, and nothing is dropped ───────────────────────────
    local started, finish_fns = {}, {}
    for _ = 1, 10 do
      local out = fresh()
      cache.ensure(out, function(done)
        started[#started + 1] = out
        finish_fns[#finish_fns + 1] = done
      end, function() end)
    end

    H.eq(#started, 3, "only as many renders start as there are slots")
    H.eq(running(), 3, "")
    H.eq(waiting(), 7, "the rest wait rather than spawning")

    -- Finishing one frees exactly one slot.
    table.remove(finish_fns, 1)(nil)
    H.eq(#started, 4, "a finished render lets the next one start")
    H.eq(running(), 3, "and the bound still holds")

    -- Drained FIFO with a `while`, not a counted loop: finishing one starts the
    -- next, which appends its own `done` — a `for i = #finish_fns, 1, -1` reads
    -- the length once and never reaches them.
    while #finish_fns > 0 do
      table.remove(finish_fns, 1)(nil)
    end
    vim.wait(500, function()
      return running() == 0 and waiting() == 0
    end, 5)
    H.eq(#started, 10, "every queued render eventually runs — the queue delays, it does not drop")
    H.eq(running(), 0, "")

    -- ── a render that reports twice must not free two slots ───────────────
    -- The one failure mode a concurrency bound cannot have: over-releasing
    -- lets the queue run past its own limit for the rest of the session.
    local double_started = {}
    local double_done
    cache.ensure(fresh(), function(done)
      double_started[#double_started + 1] = true
      double_done = done
    end, function() end)
    H.eq(running(), 1, "")
    double_done(nil)
    double_done(nil)
    vim.wait(200, function()
      return running() == 0
    end, 5)
    H.eq(running(), 0, "a second `done` is ignored rather than counted")

    -- ── priority order: high first, low last ──────────────────────────────
    config.setup({ render_concurrency = 1 })

    local order = {}
    local pending = {}
    ---@param label string
    ---@param priority string|nil
    local function submit(label, priority)
      local out = fresh()
      cache.ensure(out, function(done)
        order[#order + 1] = label
        pending[#pending + 1] = done
      end, function() end, priority and { priority = priority } or nil)
    end

    -- The first one takes the only slot, so the three after it queue and their
    -- order is the queue's decision rather than submission order.
    submit("occupier")
    submit("low-1", "low")
    submit("normal-1")
    submit("high-1", "high")

    H.eq(order[1], "occupier", "the first submission takes the free slot")
    H.eq(#order, 1, "and the rest are waiting")

    for _ = 1, 3 do
      local done = table.remove(pending, 1)
      done(nil)
      vim.wait(200, function()
        return #pending > 0 or running() == 0
      end, 5)
    end

    H.eq_list(
      order,
      { "occupier", "high-1", "normal-1", "low-1" },
      "a playback window jumps the queue and a prefetch gives way — measured at 243 ms against 1111 ms when it did not"
    )

    while #pending > 0 do
      table.remove(pending, 1)(nil)
    end
    vim.wait(500, function()
      return running() == 0 and waiting() == 0
    end, 5)

    -- ── an unknown priority is treated as normal, not as an error ─────────
    order = {}
    submit("occupier-2")
    submit("nonsense", "whenever")
    submit("high-2", "high")
    for _ = 1, 2 do
      local done = table.remove(pending, 1)
      done(nil)
      vim.wait(200, function()
        return #pending > 0 or running() == 0
      end, 5)
    end
    H.eq(order[2], "high-2", "an unrecognised priority does not become the highest one")
    while #pending > 0 do
      table.remove(pending, 1)(nil)
    end
    vim.wait(500, function()
      return running() == 0 and waiting() == 0
    end, 5)

    -- ── giving up on a queued render takes it out of the queue ────────────
    -- The case this is for: a hover that came and went while its decode was
    -- still waiting for a slot. Running it later is work for nobody.
    order = {}
    submit("occupier-3")

    local abandoned_started = false
    local handle = cache.ensure(fresh(), function(done)
      abandoned_started = true
      pending[#pending + 1] = done
    end, function() end)

    H.eq(waiting(), 1, "it is queued behind the occupier")
    handle.cancel()
    H.eq(waiting(), 0, "and cancelling removes it")

    table.remove(pending, 1)(nil)
    vim.wait(300, function()
      return running() == 0
    end, 5)
    H.eq(abandoned_started, false, "the abandoned render never ran at all")

    -- ── but one caller giving up does not take the render from another ────
    config.setup({ render_concurrency = 1 })
    order = {}
    submit("occupier-4")

    local shared = fresh()
    local shared_started = false
    local a_called, b_called = false, false
    local handle_a = cache.ensure(shared, function(done)
      shared_started = true
      pending[#pending + 1] = done
    end, function()
      a_called = true
    end)
    cache.ensure(shared, function()
      error("the second caller must join, not render a second time")
    end, function()
      b_called = true
    end)

    H.eq(waiting(), 1, "two callers for one output are one queued render")
    handle_a.cancel()
    H.eq(waiting(), 1, "and the first giving up leaves the second's render queued")

    table.remove(pending, 1)(nil) -- release the occupier
    vim.wait(300, function()
      return shared_started
    end, 5)
    H.eq(shared_started, true, "which then runs")
    table.remove(pending, 1)(nil)
    vim.wait(300, function()
      return b_called
    end, 5)
    H.eq(b_called, true, "and answers the caller that stayed")
    H.eq(a_called, false, "but not the one that left")
  end)

  config.setup({})
  H.ok(ok, "cache_queue_spec: " .. tostring(err))
end
