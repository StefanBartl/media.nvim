-- REL-20: `setup({ keymaps = false })` is the natural way to say "bind nothing". `keymaps` is a table
-- in the defaults, so the boolean used to replace it in the merge and the keymap setup indexed `false`.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local config = require("media.config")
  local media = require("media")

  --- Is a normal-mode mapping with this lhs defined right now?
  ---@param lhs string
  ---@return boolean
  local function mapped(lhs)
    local expanded = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if
        m.lhs == lhs
        or m.lhs == expanded
        or m.lhs == lhs:gsub("<leader>", vim.g.mapleader or "\\")
      then
        return true
      end
    end
    return false
  end

  -- ── the config layer ──────────────────────────────────────────────────
  local passed = { keymaps = false }
  config.setup(passed)
  H.eq(type(config.get().keymaps), "table", "keymaps = false keeps the group a table")
  H.eq(config.get().keymaps.preset, false, "keymaps = false is the existing preset = false switch")
  H.eq(passed.keymaps, false, "the caller's table is not rewritten")

  config.setup({ keymaps = true })
  H.eq(config.get().keymaps.preset, true, "keymaps = true keeps the defaults")
  H.eq(config.get().keymaps.probe, "<leader>Mp", "... including the keys")

  config.setup({ keymaps = "nonsense" })
  H.eq(
    config.get().keymaps.preset,
    true,
    "a value that is neither boolean nor table falls back to the defaults"
  )

  config.setup({ keymaps = { probe = "<leader>Xp" } })
  H.eq(config.get().keymaps.probe, "<leader>Xp", "the table form still merges")
  H.eq(config.get().keymaps.frame, "<leader>Mf", "... over the defaults")

  -- ── the whole setup() ─────────────────────────────────────────────────
  local ok, err = pcall(media.setup, { keymaps = false })
  H.ok(ok, "setup({ keymaps = false }) must not raise: " .. tostring(err))
  H.ok(not mapped("<leader>Mp"), "keymaps = false binds nothing")

  -- the family-wide spelling `keymaps.enable = false` binds nothing as well
  ok, err = pcall(media.setup, { keymaps = { enable = false } })
  H.ok(ok, "setup({ keymaps = { enable = false } }) must not raise: " .. tostring(err))
  H.ok(not mapped("<leader>Mp"), "keymaps.enable = false binds nothing")

  ok, err = pcall(media.setup, { keymaps = true })
  H.ok(ok, "setup({ keymaps = true }) must not raise: " .. tostring(err))
  H.ok(mapped("<leader>Mp"), "keymaps = true still binds the defaults")

  ok, err = pcall(media.setup, {})
  H.ok(ok, "the default setup still works: " .. tostring(err))

  config.setup({})
end
