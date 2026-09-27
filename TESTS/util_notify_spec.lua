-- TESTS/util_notify_spec.lua — media.util.notify's no-lib.nvim fallback: it
-- must keep the "media.nvim" identification every pre-existing vim.notify
-- call site in this plugin used to pass explicitly, without overriding a
-- caller-supplied title (scratch()'s dynamic per-file title relies on this).

---@param H table
return function(H)
  local original_preload = package.preload["lib.nvim.notify"]
  local original_loaded = package.loaded["lib.nvim.notify"]
  package.loaded["lib.nvim.notify"] = nil
  package.preload["lib.nvim.notify"] = function()
    error("simulated: lib.nvim.notify not installed")
  end
  package.loaded["media.util.notify"] = nil
  local notify = require("media.util.notify")

  local seen
  local original_notify = vim.notify
  vim.notify = function(msg, level, opts)
    seen = { msg = msg, level = level, opts = opts }
  end

  notify.info("hello")
  H.ok(
    seen and seen.opts and seen.opts.title == "media.nvim",
    "info() with no opts still gets the default title"
  )

  notify.warn("hi", { title = "custom" })
  H.eq(seen.opts.title, "custom", "a caller-supplied title is not overridden by the default")

  notify.error("oops")
  H.eq(seen.opts.title, "media.nvim", "error() with no opts also gets the default title")

  notify.notify("hey", vim.log.levels.WARN)
  H.eq(seen.level, vim.log.levels.WARN, "notify() forwards the given level")
  H.eq(seen.opts.title, "media.nvim", "notify() with no opts also gets the default title")

  vim.notify = original_notify
  package.preload["lib.nvim.notify"] = original_preload
  package.loaded["lib.nvim.notify"] = original_loaded
  package.loaded["media.util.notify"] = nil -- force a clean re-resolve for anything requiring it later
end
