---@module 'media.bindings.autocmds'
---@brief What this plugin does on its own — which is one thing.
---@description
--- **There is deliberately no autocommand that reacts to opening a media file.**
--- It is the obvious one to write (`BufReadCmd *.mp4` → show a poster frame
--- instead of the bytes), and it is the wrong thing for a plugin to claim: it
--- takes over a filetype globally, it fights netrw, oil and every file tree that
--- has its own opinion, and it turns a `:e` typo into a decode. A consumer that
--- wants that behaviour builds it out of `media.frame` in three lines and owns
--- the decision.
---
--- What is left is housekeeping: the binary lookup caches a negative answer for
--- the session, and installing ffmpeg while Neovim is open should not require
--- restarting it.

local M = {}

---@return nil
function M.setup()
  local group = vim.api.nvim_create_augroup("MediaNvim", { clear = true })

  -- `VimResume` fires when the editor comes back from `<C-z>` or a suspend,
  -- which is exactly the shape of "I went to a shell to install the thing that
  -- was missing". Cheap to act on: the next lookup does three `fs_stat` calls.
  vim.api.nvim_create_autocmd("VimResume", {
    group = group,
    desc = "media.nvim: look for ffmpeg again after a suspend",
    callback = function()
      require("media.core.bin").reset()
    end,
  })
end

return M
