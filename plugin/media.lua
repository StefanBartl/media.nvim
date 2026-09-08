-- Guard: load only once, only inside Neovim.
if vim.g.loaded_media then return end
vim.g.loaded_media = true

-- Nothing is registered here. `:Media` and the four keys come from
-- require("media").setup(), which lazy.nvim runs for you via `opts = {}`.
-- Registering eagerly from a plugin file would mean requiring lib.nvim's
-- command composer on every startup, for a command most sessions never use.
