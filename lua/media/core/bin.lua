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
--- moves, and there the loop is the cost.
---
--- **The cache key includes `config.get().bin[name]`**, not just `name`: a
--- `setup()` call that changes `bin.ffmpeg` is a different answer, and is
--- seen on the very next `find()`, no `M.reset()` needed. `M.reset()` still
--- exists for what a config diff cannot see: installing ffmpeg, or editing
--- PATH, with Neovim already open.

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
---@param name string binary name, e.g. "ffmpeg", "ffprobe", "mpv"
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

---@class Media.Bin.CacheEntry
---@field cfg string|nil     # `config.get().bin[name]` at the time this was resolved
---@field val string|false   # false = "looked for, not found"

---@type table<string, Media.Bin.CacheEntry>
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
---
--- Not only "ffmpeg"|"ffprobe": `media.core.audio` looks up "mpv" through the
--- same function, for the same reason — the winget/scoop shim problem this
--- module exists for is not specific to ffmpeg's two binaries.
---@param name string "ffmpeg", "ffprobe", "mpv", …
---@return string|nil
function M.find(name)
  local configured = require("media.config").get().bin[name]

  local cached = resolved[name]
  if cached ~= nil and cached.cfg == configured then return cached.val or nil end

  if type(configured) == "string" and configured ~= "" then
    -- An explicit path is honoured as given, including when it does not exist:
    -- the error the user then gets names their own setting, which is a better
    -- place to start looking than "ffmpeg not found".
    resolved[name] = { cfg = configured, val = configured }
    return configured
  end

  local ok, executable = pcall(require, "lib.nvim.cross.executable")
  if ok and executable.exists(name) then
    resolved[name] = { cfg = configured, val = name }
    return name
  end
  if not ok and vim.fn.executable(name) == 1 then
    resolved[name] = { cfg = configured, val = name }
    return name
  end

  for _, candidate in ipairs(well_known(name)) do
    if is_file(candidate) then
      resolved[name] = { cfg = configured, val = candidate }
      return candidate
    end
  end

  resolved[name] = { cfg = configured, val = false }
  return nil
end

--- Forget what was found, so the next `find` looks again. A config change
--- already invalidates itself (see the cache key above); this is for what a
--- config diff cannot see — ffmpeg installed, or PATH edited, while Neovim
--- was already open.
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
