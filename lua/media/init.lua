---@module 'media'
---@brief media.nvim — what is in this media file, and one picture of it.
---@description
--- **The gap this fills.** Neovim's ecosystem can draw a picture and can read a
--- PDF, and both of those are somebody's plugin already. Nothing turns a video
--- into either. A `.mp4` under the cursor is, everywhere, a size in bytes and
--- the word "binary" — not because showing something would be hard, but because
--- the one process that produces a still had no home.
---
--- This is that home, and it is deliberately the same shape as
--- [pdfport.nvim](https://github.com/StefanBartl/pdfport.nvim): an external
--- toolchain, wrapped once, exposed as two verbs, consumed by anything that
--- wants them. `images.nvim` says of PDFs that it *"draws pictures; it does not
--- read PDFs, and it does not want to"* — the same sentence, with "videos" in
--- it, is why this repository exists rather than another branch inside that one.
---
--- **What this plugin does not do.** It does not play video. Nothing in a
--- terminal Neovim can: the only image protocol that reaches the terminal from
--- inside Neovim carries a whole picture per write and has no notion of a
--- frame, and Neovim repaints over anything drawn between its own redraws.
--- `media.play` hands the file to something that can, and that is the honest
--- end of it. See `docs/ROADMAP.md` for the two things that would move the line
--- and why neither is free.
---
--- **The public surface.**
---
--- ```lua
--- local media = require("media")
---
--- media.available()                 -- ffmpeg and ffprobe both reachable?
--- media.is_video(path)              -- by extension, no process started
--- media.probe(path, function(p, err) end)          -- duration, size, codecs
--- media.frame(path, { at = "10%" }, function(png, err) end)  -- a still
--- media.frames(path, { from = 0, count = 24 }, function(pngs, err) end)  -- a run
--- media.sheet(path, { rows = 3, cols = 4 }, function(png, err) end)
--- media.play(path)                  -- hand it to a real player
--- ```
---
--- Every callback runs exactly once and on the main loop, so it may touch the
--- Neovim API. Consumers are expected to `pcall(require, "media")` and carry on
--- without it — that is how `hover.nvim` uses this, and it is the contract that
--- keeps a missing optional dependency from being an error anywhere.

local M = {}

--- Configure the plugin. Optional: every default is chosen to be useful on its
--- own, and nothing here has to run for `:Media` to work.
---@param opts Media.Opts|nil
---@return nil
function M.setup(opts)
  require("media.config").setup(opts)
  require("media.bindings").setup()
end

--- Whether this plugin can do anything at all right now: both binaries found.
---@return boolean
function M.available()
  return require("media.core.bin").available()
end

---@param path string|nil
---@return boolean
function M.is_video(path)
  return require("media.formats").is_video(path)
end

---@param path string|nil
---@return boolean
function M.is_audio(path)
  return require("media.formats").is_audio(path)
end

---@param path string|nil
---@return boolean
function M.is_media(path)
  return require("media.formats").is_media(path)
end

--- What `ffprobe` says about `path`.
---@param path string
---@param callback fun(probe: Media.Probe|nil, err: string|nil): nil
---@return nil
function M.probe(path, callback)
  return require("media.core.probe").probe(path, callback)
end

--- What is already known about `path`, without starting a process. `nil` when
--- nothing is — this never blocks and never renders.
---@param path string
---@return Media.Probe|nil
function M.probed(path)
  return require("media.core.probe").cached(path)
end

--- A PNG of one still out of `path`, rendered once and cached on disk.
---@param path string
---@param opts Media.FrameOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.frame(path, opts, callback)
  return require("media.core.frame").frame(path, opts, callback)
end

--- A run of stills out of `path`, in order, as PNGs on disk.
---
--- The decode half of playback: one ffmpeg pass produces the whole run, and
--- the returned handle cancels it. This plugin still does not play anything —
--- it now hands a consumer that can draw cells something to draw.
---@param path string
---@param opts Media.FramesOpts|nil
---@param callback fun(pngs: string[]|nil, err: string|nil): nil
---@return Media.Frames.Handle
function M.frames(path, opts, callback)
  return require("media.core.frames").frames(path, opts, callback)
end

--- A PNG contact sheet of `path` — the whole running time as one grid.
---@param path string
---@param opts Media.SheetOpts|nil
---@param callback fun(png: string|nil, err: string|nil): nil
---@return nil
function M.sheet(path, opts, callback)
  return require("media.core.sheet").sheet(path, opts, callback)
end

--- Hand `path` to a real player — the configured one, or the system's.
---@param path string
---@return boolean ok
---@return string|nil err
function M.play(path)
  return require("media.core.play").play(path)
end

--- Forget every rendered still and every remembered probe.
---@return integer removed  # files deleted from the disk cache
function M.clear_cache()
  require("media.core.probe").clear()
  return require("media.core.cache").clear()
end

return M
