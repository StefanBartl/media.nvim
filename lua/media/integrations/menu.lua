---@module 'media.integrations.menu'
---@brief The dashboard's actions, on the right mouse button.
---@description
--- `lib.nvim.contextmenu`'s "owns its buffer" shape — the one its own header
--- names a dashboard as the example of. The items come from
--- `media.hub.actions`, unchanged: one list feeding both the keyboard path
--- (`a`, through `vim.ui.select`) and the mouse, because a menu and a keymap
--- that each build their own list are a pair that drifts, which is the defect
--- `media.bindings.usrcmds`' own header was written about.
---
--- **An unavailable action is shown, not dropped — which is a deliberate
--- departure from how `contextmenu.entry` gates.** That function omits an
--- entry whose `available` argument is falsy, and it is right to for the usual
--- case: a menu full of things that cannot happen is noise. A dashboard is the
--- other case. Its whole job is to say what is *possible* here, and an OCR row
--- that silently vanishes on a machine without tesseract teaches the reader
--- that media.nvim cannot OCR — which is false, and unfalsifiable from where
--- they are standing. So the entry is built as available, carries its reason
--- in the right-aligned hint `rtxt` is for, and explains instead of running
--- when picked. `images.ocr` applies the same principle to a missing tesseract
--- language.

-- LuaJIT's global, which is what Neovim runs and what `.luarc.json` and
-- `.luacheckrc` both declare. `table.unpack` is the 5.2+ spelling and is not
-- in either's standard library here.
local unpack = unpack

local M = {}

--- The menu items for one row (or the marked set), as
--- `lib.nvim.contextmenu` wants them.
---
--- Public and pure-ish so the shape is assertable without a mouse, a menu
--- renderer, or a float.
---@param entries Media.Hub.Entry[]
---@param on_pick fun(action: Media.Hub.Action, tool: Media.Hub.Tool): nil
---@return table[]
function M.items(entries, on_pick)
  local ok, contextmenu = pcall(require, "lib.nvim.contextmenu")
  if not ok or #entries == 0 then return {} end

  local actions = require("media.hub.actions")
  local kind = entries[1].kind

  local out = {}
  local built = {}
  for _, action in ipairs(actions.list(kind)) do
    -- Over a marked set, only what a batch means anything for — the same rule
    -- `media.hub.dashboard`'s own chooser applies.
    if #entries == 1 or actions.batchable(action) then
      local tool = actions.availability(action, kind)
      built[#built + 1] = contextmenu.entry(true, action.label, function()
        on_pick(action, tool)
      end, tool.ok and nil or (tool.reason or "unavailable"), tool.ok and {} or {
        hl = "Comment",
      })
    end
  end

  if #built > 0 then
    local heading = #entries == 1 and "media" or ("media — %d marked"):format(#entries)
    contextmenu.group(out, contextmenu.heading(heading), unpack(built))
  end
  return out
end

--- Bind the right mouse button on the dashboard's buffer.
---
--- Soft, like everything else that reaches out of this plugin: without
--- lib.nvim there is no menu and the keyboard path is untouched.
---@param bufnr integer
---@param winid integer
---@param state { entries: Media.Hub.Entry[], marked: table<string, boolean> }
---@return nil
function M.bind(bufnr, winid, state)
  local ok, contextmenu = pcall(require, "lib.nvim.contextmenu")
  if not ok or type(contextmenu.bind_buffer) ~= "function" then return end

  contextmenu.bind_buffer(bufnr, function()
    -- Read at open time, not at bind time: which rows are marked, and which
    -- row the click landed on, are both later facts than this binding.
    local chosen = {}
    for _, entry in ipairs(state.entries) do
      if state.marked[entry.path] then chosen[#chosen + 1] = entry end
    end
    if #chosen == 0 and vim.api.nvim_win_is_valid(winid) then
      local under = state.entries[vim.api.nvim_win_get_cursor(winid)[1]]
      if under then chosen = { under } end
    end

    return M.items(chosen, function(action, tool)
      require("media.hub.dashboard").pick(chosen, action, tool)
    end)
  end)
end

return M
