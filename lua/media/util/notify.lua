---@module 'media.util.notify'
---@brief The single notifier for media.nvim.
---@description
--- `lib.nvim` is a soft dependency (see README's "All of the above are
--- soft" section): used when available, a plain `vim.notify` fallback
--- otherwise -- media.nvim's own docs already state that stance ("without
--- it ... the float dashboard becomes a `vim.notify` list").
---
--- Resolved once at first `require`, like every other soft-dependency
--- lookup in this plugin (`M.show_image`'s `images`/`lib.nvim.cross.open_default`
--- probes, `scratch`'s `lib.nvim.window.make_scratch` probe): a single
--- module-level check, not re-done on every call.

local ok, lib = pcall(require, "lib.nvim.notify")
if ok then return lib.create("[media.nvim]", { popup = true, source = "media" }) end

---Every pre-existing vim.notify call site in this plugin passed an explicit
---`{ title = "media.nvim" }` (or a dynamic title, for scratch()'s fallback).
---A default here keeps that identification for callers that now omit opts
---entirely, without overriding one a caller does supply (e.g. a filename).
---@param opts table|nil
---@return table
local function with_default_title(opts)
  if opts and opts.title then return opts end
  return vim.tbl_extend("force", opts or {}, { title = "media.nvim" })
end

return {
  notify = function(msg, level, opts)
    vim.notify(msg, level or vim.log.levels.INFO, with_default_title(opts))
  end,
  info = function(msg, opts)
    vim.notify(msg, vim.log.levels.INFO, with_default_title(opts))
  end,
  warn = function(msg, opts)
    vim.notify(msg, vim.log.levels.WARN, with_default_title(opts))
  end,
  error = function(msg, opts)
    vim.notify(msg, vim.log.levels.ERROR, with_default_title(opts))
  end,
}
