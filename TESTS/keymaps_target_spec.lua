-- media.bindings.keymaps.target(): the cursor-under-file fallback must never
-- throw, even where `<cfile>` genuinely has nothing to answer (SEC-34) --
-- `vim.fn.expand("<cfile>")` raises `E446` on an empty/whitespace line rather
-- than returning "", and every one of the four global keys goes through this.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local keymaps = require("media.bindings.keymaps")

  local original = vim.api.nvim_get_current_buf()
  local scratch = vim.api.nvim_create_buf(false, true)

  local ok, err = pcall(function()
    vim.api.nvim_set_current_buf(scratch)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local target = keymaps.target()
    H.eq(target, nil, "nothing under the cursor and an unnamed buffer is nil, not a crash")
  end)

  pcall(vim.api.nvim_set_current_buf, original)
  pcall(vim.api.nvim_buf_delete, scratch, { force = true })

  H.ok(ok, "keymaps_target_spec: " .. tostring(err))
end
