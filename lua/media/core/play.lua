---@module 'media.core.play'
---@brief Hand a file to something that can actually play it.
---@description
--- This plugin renders stills; it does not play anything, and inside a terminal
--- Neovim nothing can. The honest end of the feature is therefore a handoff,
--- and it is worth having here rather than in every consumer because two of the
--- three things it has to get right are not obvious.
---
--- **`detach` is not used, and must not be.** On Windows,
--- `jobstart(argv, { detach = true })` never runs a *console* program at all:
--- libuv's `DETACHED_PROCESS` leaves the child without standard handles, and an
--- interpreter exits before its first statement — while `jobstart` still
--- returns a valid job id, so it looks like success. `vim.system(argv, {})`
--- without waiting is the form that works for both console and GUI players.
---
--- **The player's window will open behind the terminal, and that is not a bug
--- here.** Windows grants `SetForegroundWindow` only to the process that owns
--- the foreground window; inside a terminal that is the terminal host, not
--- `nvim.exe`, so a window spawned from here is created behind everything.
--- Raising it needs the `AttachThreadInput` dance against a window handle this
--- module does not have and should not go looking for. Under a GUI Neovim the
--- same code puts the player in front, which is what makes the difference look
--- intermittent rather than structural — it is worth knowing before filing it
--- as a defect.
---
--- **No configured player is the good default.** The system handler is a choice
--- the user already made once, in their desktop environment, and it is right
--- more often than any guess this plugin could make.

local M = {}

--- The configured player as an argv prefix, or nil when none is configured or
--- the configured one cannot be found.
---@return string[]|nil argv
---@return string|nil err
function M.player()
  local player = require("media.config").get().player
  if player == nil then return nil, nil end

  ---@type string[]
  local argv
  if type(player) == "string" then
    argv = { player }
  elseif type(player) == "table" and type(player[1]) == "string" then
    argv = vim.deepcopy(player)
  else
    return nil, "`player` must be a string or an argv list"
  end

  local ok, executable = pcall(require, "lib.nvim.cross.executable")
  local found = ok and executable.exists(argv[1]) or (not ok and vim.fn.executable(argv[1]) == 1)
  if not found then return nil, ("configured player not found: %s"):format(argv[1]) end

  return argv, nil
end

--- Play `path`, in a configured player or in whatever the system opens it with.
---@param path string
---@return boolean ok
---@return string|nil err
function M.play(path)
  if type(path) ~= "string" or path == "" then return false, "no path given" end

  local argv, err = M.player()
  if err then return false, err end

  if argv then
    argv[#argv + 1] = path
    -- Deliberately not awaited: the point is that the player outlives this
    -- call. Its exit code is of no interest to anybody here, and waiting for it
    -- would block the editor for the length of the film.
    vim.system(argv, {})
    return true, nil
  end

  local ok_open, open_default = pcall(require, "lib.nvim.cross.open_default")
  if ok_open then return open_default(path) end

  if type(vim.ui.open) == "function" then
    local ok = pcall(vim.ui.open, path)
    return ok, ok and nil or "vim.ui.open failed"
  end

  return false, "no way to open this file — set `player`, or install lib.nvim"
end

return M
