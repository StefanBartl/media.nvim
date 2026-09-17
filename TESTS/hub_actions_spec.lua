-- media.hub.actions: the action table, the default `<CR>` picks, and the
-- batch.
--
-- The batch is the half worth real assertions: it is sequential, it survives a
-- failure in the middle, it reports a ratio with a real denominator, and it can
-- be stopped. Every one of those is invisible until the day it is wrong, and
-- three of them only show up over more than one file.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch

---@param H table
return function(H)
  local actions = require("media.hub.actions")

  -- ── the table, per kind ─────────────────────────────────────────────────
  ---@param kind string
  ---@param id string
  ---@return boolean
  local function offers(kind, id)
    for _, action in ipairs(actions.list(kind)) do
      if action.id == id then return true end
    end
    return false
  end

  H.ok(offers("image", "ocr_sidecar"), "an image can be OCR'd to a sidecar")
  H.ok(offers("pdf", "text_sidecar"), "a PDF can be extracted to one")
  H.ok(offers("video", "srt"), "a video can become subtitles")
  H.ok(offers("audio", "srt"), "and so can audio — both reach the same dispatcher")
  H.ok(offers("audio", "translate"), "the roadmap's 'transcribe + translate' is there")
  H.falsy(offers("image", "srt"), "an image cannot: there are no timestamps in a still")
  H.falsy(offers("pdf", "srt"), "")

  -- The navigation three are offered for every kind, including the ones with
  -- no text operation at all.
  for _, kind in ipairs({ "image", "pdf", "audio", "video", "other" }) do
    H.ok(offers(kind, "open_source"), kind .. " can always open its own file")
    H.ok(offers(kind, "describe"), "")
  end
  H.eq(#actions.list("other"), 3, "a kind with no text operation gets the navigation three only")

  -- Video reuses audio's table by reference on purpose — a second copy is how
  -- the two drift the first time one gains an action.
  H.eq(#actions.list("video"), #actions.list("audio"), "video and audio offer the same actions")

  -- ── what `<CR>` does, which must never be wasted work ───────────────────
  local missing = actions.default_for({ kind = "video", status = "missing" })
  H.ok(missing ~= nil, "")
  H.eq(missing.id, "transcribe_sidecar", "a missing transcript is worth making")
  H.eq(
    missing.mode,
    "sidecar",
    "and to a sidecar, not a buffer — a batch of buffers is a stack of windows nobody asked for"
  )

  local stale = actions.default_for({ kind = "video", status = "stale" })
  H.eq(stale.id, "transcribe_sidecar", "a stale one is worth remaking, for the same reason")

  local fine = actions.default_for({ kind = "video", status = "ok" })
  H.eq(
    fine.id,
    "open_text",
    "a current transcript is worth READING — re-running it would spend minutes producing what is already on disk"
  )
  H.eq(fine.needs_text, false, "and costs nothing")

  H.eq(actions.default_for({ kind = "image", status = "missing" }).id, "ocr_sidecar", "")
  H.eq(actions.default_for({ kind = "pdf", status = "missing" }).id, "text_sidecar", "")
  H.eq(actions.default_for({ kind = "other", status = "none" }), nil, "")

  -- ── which actions a batch means anything for ────────────────────────────
  H.eq(actions.batchable({ id = "ocr_sidecar", needs_text = true }), true, "")
  H.eq(
    actions.batchable({ id = "open_source", needs_text = false }),
    false,
    "'open the source file' over twelve rows is twelve windows, not a batch"
  )

  -- ── availability is the text pipeline's answer, once ────────────────────
  local saved_text = package.loaded["media.hub.text"]
  package.loaded["media.hub.text"] = {
    tool = function(kind)
      if kind == "image" then return { ok = false, tool = "tesseract", reason = "not here" } end
      return { ok = true, tool = "fake" }
    end,
  }

  local ok, err = pcall(function()
    H.eq(
      actions.availability({ needs_text = true }, "image").ok,
      false,
      "an action that needs a tool asks media.hub.text, so there is one answer to that question"
    )
    H.eq(
      actions.availability({ needs_text = false }, "image").ok,
      true,
      "and opening a file needs no tool at all"
    )

    -- ── the batch ─────────────────────────────────────────────────────────
    ---@type Media.Hub.Entry[]
    local entries = {
      { path = "/r/a.mp4", name = "a.mp4", kind = "video", status = "missing" },
      { path = "/r/b.mp4", name = "b.mp4", kind = "video", status = "missing" },
      { path = "/r/c.mp4", name = "c.mp4", kind = "video", status = "missing" },
    }

    local run_order, delivered = {}, {}
    package.loaded["media.hub.text"] = {
      tool = function()
        return { ok = true, tool = "fake" }
      end,
      run = function(path, _, cb)
        run_order[#run_order + 1] = path
        -- The middle one fails, and the batch must carry on: a file that
        -- cannot be read is one row's problem, and two transcripts are worth
        -- more than an error message.
        if path == "/r/b.mp4" then
          cb(nil, "ffmpeg exited with 1")
        else
          cb({ kind = "video", text = "x", tool = "fake" }, nil)
        end
        return { cancel = function() end }
      end,
      deliver = function(path, _, mode)
        delivered[#delivered + 1] = { path = path, mode = mode }
        return true, nil
      end,
    }

    local steps = {}
    local result
    actions.run_batch(entries, {
      id = "transcribe_sidecar",
      label = "Transcribe → sidecar",
      mode = "sidecar",
      needs_text = true,
    }, function(i, total, entry)
      steps[#steps + 1] = { i = i, total = total, name = entry.name }
    end, function(done, failures, cancelled)
      result = { done = done, failures = failures, cancelled = cancelled }
    end)

    vim.wait(2000, function()
      return result ~= nil
    end, 5)

    H.ok(result ~= nil, "the batch called back")
    H.eq(#run_order, 3, "every file was run")
    H.eq_list(run_order, { "/r/a.mp4", "/r/b.mp4", "/r/c.mp4" }, "in order, one after another")
    H.eq(
      result.done,
      2,
      "the two that worked were delivered — a failure in the middle does not abandon the rest"
    )
    H.eq(#result.failures, 1, "and the one that did not is reported")
    H.eq(result.failures[1].name, "b.mp4", "by name, so a reader can go to it")
    H.eq(result.failures[1].err, "ffmpeg exited with 1", "with the tool's own message")
    H.eq(result.cancelled, false, "")

    H.eq(#steps, 3, "each file was announced before it ran")
    H.eq(steps[1].i, 1, "")
    H.eq(
      steps[1].total,
      3,
      "with a real denominator — files done of files asked, unlike a percentage inside one run"
    )
    H.eq(steps[3].i, 3, "")
    H.eq(steps[2].name, "b.mp4", "named by the row, not the absolute path")

    H.eq(#delivered, 2, "only successes reach the writer")
    H.eq(delivered[1].mode, "sidecar", "with the action's own mode, not the configured default")

    -- ── a delivery failure counts as a failure, not a success ────────────
    package.loaded["media.hub.text"].deliver = function()
      return false, "disk full"
    end
    result = nil
    actions.run_batch(
      { entries[1] },
      { id = "x", label = "X", mode = "sidecar", needs_text = true },
      function() end,
      function(done, failures)
        result = { done = done, failures = failures }
      end
    )
    vim.wait(2000, function()
      return result ~= nil
    end, 5)
    H.eq(result.done, 0, "a run that produced text but could not write it is not a success")
    H.eq(result.failures[1].err, "disk full", "")

    -- ── cancelling stops the batch after the item in flight ──────────────
    local started = 0
    package.loaded["media.hub.text"] = {
      tool = function()
        return { ok = true, tool = "fake" }
      end,
      run = function(_, _, cb)
        started = started + 1
        vim.schedule(function()
          cb({ kind = "video", text = "x", tool = "fake" }, nil)
        end)
        return { cancel = function() end }
      end,
      deliver = function()
        return true, nil
      end,
    }

    result = nil
    local job = actions.run_batch(
      entries,
      { id = "x", label = "X", mode = "sidecar", needs_text = true },
      function(i)
        -- Give up while the first one is in flight.
        if i == 1 then vim.schedule(function() end) end
      end,
      function(done, failures, cancelled)
        result = { done = done, failures = failures, cancelled = cancelled }
      end
    )
    job.cancel()
    vim.wait(2000, function()
      return result ~= nil
    end, 5)

    H.eq(result.cancelled, true, "the batch reports that it was stopped rather than finished")
    H.ok(started < 3, "and did not go on to start every remaining file")
  end)

  package.loaded["media.hub.text"] = saved_text
  H.ok(ok, "hub_actions_spec: " .. tostring(err))
end
