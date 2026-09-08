---@module 'media.core.bin'
---@brief Finding `ffmpeg` and `ffprobe`.
---@description
--- **Why this is not one `vim.fn.executable` call.** On Windows, "installed"
--- and "reachable" routinely come apart, and the two most common ways to
--- install ffmpeg are both examples: winget drops shims in
--- `%LOCALAPPDATA%/Microsoft/WinGet/Links`, scoop in `~/scoop/shims`, and both
--- add that directory to the *user* PATH — which a shell, a terminal and every
--- process started from them inherited at login and will not see until they
--- restart. The result looks exactly like "not installed" to somebody who
--- installed it five minutes ago.
---
--- This is the same exception `images.ocr` makes for tesseract, made for the
--- same reason and kept to the same shape: PATH first, well-known locations
--- only when PATH has already come up empty, and an explicit path in the
--- configuration always wins over both.
---
--- **The answer is cached per session**, including the negative one. Both
--- `probe` and `frame` ask before every run, a miss costs three `fs_stat`
--- calls, and neither number matters once — but a hover asks while a cursor
--- moves, and there the loop is the cost. `M.reset()` exists for the case the
--- cache is wrong about: installing ffmpeg with Neovim already open.

local M = {}

local uv = vim.uv or vim.loop

--- Directories probed when PATH has nothing, per binary name.
---
--- Not a general habit — this plugin looks up nothing else anywhere but PATH.
--- The list is the four installers that exist in practice on Windows (winget,
--- scoop, chocolatey, and the "unzip it to C:\ffmpeg" release build the
--- official download page produces), plus the two Unix prefixes that a
--- Homebrew or `/usr/local` install uses when a login shell was not the parent
--- of this process.
---@param name string "ffmpeg" or "ffprobe"
---@return string[]
local function well_known(name)
  local home = uv.os_homedir() or ""
  local localapp = os.getenv("LOCALAPPDATA") or ""
  return {
    localapp .. "/Microsoft/WinGet/Links/" .. name .. ".exe",
    home .. "/scoop/shims/" .. name .. ".exe",
    "C:/ProgramData/chocolatey/bin/" .. name .. ".exe",
    "C:/ffmpeg/bin/" .. name .. ".exe",
    "/opt/homebrew/bin/" .. name,
    "/usr/local/bin/" .. name,
  }
end

---@type table<string, string|false> false = "looked for, not found"
local resolved = {}

---@internal
---@param path string|nil
---@return boolean
local function is_file(path)
  if type(path) ~= "string" or path == "" then return false end
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == "file"
end

--- The command to run for `name`, or nil when it cannot be found.
---
--- Returns a *command*, not necessarily an absolute path: when the binary is on
--- PATH the bare name is what gets returned, because that is what should end up
--- in an argv — an absolute path resolved here would freeze a lookup the OS is
--- better at repeating.
---@param name "ffmpeg"|"ffprobe"
---@return string|nil
function M.find(name)
  local cached = resolved[name]
  if cached ~= nil then return cached or nil end

  local configured = require("media.config").get().bin[name]
  if type(configured) == "string" and configured ~= "" then
    -- An explicit path is honoured as given, including when it does not exist:
    -- the error the user then gets names their own setting, which is a better
    -- place to start looking than "ffmpeg not found".
    resolved[name] = configured
    return configured
  end

  local ok, executable = pcall(require, "lib.nvim.cross.executable")
  if ok and executable.exists(name) then
    resolved[name] = name
    return name
  end
  if not ok and vim.fn.executable(name) == 1 then
    resolved[name] = name
    return name
  end

  for _, candidate in ipairs(well_known(name)) do
    if is_file(candidate) then
      resolved[name] = candidate
      return candidate
    end
  end

  resolved[name] = false
  return nil
end

--- Forget what was found, so the next `find` looks again. For the case that
--- motivated the cache being wrong: ffmpeg installed while Neovim was open.
---@param name string|nil  # one binary, or all of them
---@return nil
function M.reset(name)
  if name then
    resolved[name] = nil
  else
    resolved = {}
  end
end

--- Whether both binaries are present. The plugin's single availability
--- question, asked by `media.available()`, by `:checkhealth` and by every
--- consumer deciding whether to claim a file at all.
---
--- Both, not either: `frame` needs a duration from `ffprobe` to resolve a
--- percentage offset, and a `probe` without `ffmpeg` can describe a file but
--- not show it. A consumer that got "yes" and then a missing binary would have
--- given up its own fallback for nothing.
---@return boolean
function M.available()
  return M.find("ffmpeg") ~= nil and M.find("ffprobe") ~= nil
end

return M
