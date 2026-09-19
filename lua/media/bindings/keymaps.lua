---@module 'media.bindings.keymaps'
---@brief The four global keys, declared once.
---@description
--- Each key is the command of the same name applied to the path under the
--- cursor — `<cfile>` first, the current buffer's own name second. That
--- fallback is what makes the keys useful in the two places a media file is
--- actually looked at: a file tree or a list of links (where `<cfile>` answers),
--- and a directory listing opened as a buffer (where it does not).
---
--- Binding goes through `lib.nvim.bindings.keymap`'s registry, which is what
--- makes a wrong action name in the user's table say so instead of silently
--- binding nothing. Without lib.nvim installed the same four keys are set
--- directly — the plugin is usable, it just loses the registry's diagnostics.

local M = {}

---@type string[] Declaration order: what the docs and which-key read.
M.ORDER = { "probe", "frame", "sheet", "play" }

---@type table<string, string>
M.DESCRIPTIONS = {
  probe = "describe media file",
  frame = "poster frame",
  sheet = "contact sheet",
  play = "play in external player",
}

--- The path a key acts on: `<cfile>` when it names a readable file, else the
--- buffer's own name.
---@return string|nil
function M.target()
  -- `pcall`ed: `<cfile>` throws `E446` rather than answering `""` when there
  -- is nothing under the cursor (SEC-34) — an empty or whitespace-only line
  -- must fall through to the buffer-name fallback below, not abort the key.
  local ok, cfile = pcall(vim.fn.expand, "<cfile>")
  if ok and type(cfile) == "string" and cfile ~= "" then
    local abs = vim.fn.fnamemodify(cfile, ":p")
    if vim.fn.filereadable(abs) == 1 then return abs end
    if vim.fn.filereadable(cfile) == 1 then return cfile end
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.fn.filereadable(name) == 1 then return name end
  return nil
end

---@internal
---@param action string
---@return fun(): nil
local function run(action)
  return function()
    local path = M.target()
    if not path then
      vim.notify("no media file under the cursor", vim.log.levels.WARN, { title = "media.nvim" })
      return
    end
    require("media.bindings.usrcmds").run(action, path)
  end
end

---@param cfg Media.Config.Keymaps
---@return table<string, table>
function M.actions(cfg)
  local actions = {}
  for _, name in ipairs(M.ORDER) do
    actions[name] = {
      default = cfg[name],
      desc = M.DESCRIPTIONS[name],
      rhs = run(name),
    }
  end
  return actions
end

--- Bind the four keys globally.
---@param cfg Media.Config.Keymaps
---@return nil
function M.setup(cfg)
  if cfg.preset == false then return end

  local ok, keymap = pcall(require, "lib.nvim.bindings.keymap")
  if ok then
    keymap.register("media", {
      which_key = { prefix = "<leader>M", group = "media" },
      order = M.ORDER,
      actions = M.actions(cfg),
    }, cfg)
    return
  end

  for _, name in ipairs(M.ORDER) do
    local lhs = cfg[name]
    if type(lhs) == "string" and lhs ~= "" then
      vim.keymap.set("n", lhs, run(name), { desc = "media: " .. M.DESCRIPTIONS[name] })
    end
  end
end

return M
