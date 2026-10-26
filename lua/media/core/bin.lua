---@module 'media.core.bin'
---@brief Finding `ffmpeg`, `ffprobe` and the other external tools.
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
  local out = {}
  -- An unset or empty variable is skipped, never used as "" — see `env_root`.
  local localapp = os.getenv("LOCALAPPDATA")
  if localapp and localapp ~= "" then
    out[#out + 1] = localapp .. "/Microsoft/WinGet/Links/" .. name .. ".exe"
  end
  local home = uv.os_homedir()
  if home and home ~= "" then out[#out + 1] = home .. "/scoop/shims/" .. name .. ".exe" end
  vim.list_extend(out, {
    "C:/ProgramData/chocolatey/bin/" .. name .. ".exe",
    "C:/ffmpeg/bin/" .. name .. ".exe",
    "/opt/homebrew/bin/" .. name,
    "/usr/local/bin/" .. name,
  })
  return out
end

--- Binaries that are Python console entry points (`pip install
--- openai-whisper` puts `whisper` there), and therefore land in a Python
--- `Scripts` directory rather than an installer's shim directory.
---@type table<string, true>
local PYTHON_TOOLS = { whisper = true, ["whisper-ctranslate2"] = true }

--- The subdirectories of `root`, or none when it does not exist.
---@param root string
---@return string[]
local function subdirs(root)
  local out = {}
  local handle = uv.fs_scandir(root)
  if not handle then return out end
  while true do
    local entry, kind = uv.fs_scandir_next(handle)
    if not entry then break end
    if kind == "directory" then out[#out + 1] = root .. "/" .. entry end
  end
  -- Version order, not byte order: `Python39` sorts after `Python313` as
  -- bytes, so "newest last" picked 3.9 over 3.13. Every digit run is padded
  -- before comparing. Found in review, 2026-10-26.
  local function key(s)
    return (s:gsub("%d+", function(d)
      return ("%012d"):format(tonumber(d) or 0)
    end))
  end
  table.sort(out, function(a, b)
    return key(a) < key(b)
  end)
  return out
end

--- `os.getenv(var)`, or nil when it is unset **or empty**. An empty value
--- must not become a root: `"" .. "/miniconda3"` is `/miniconda3`, which on
--- Windows is the root of the current drive — a directory any local user may
--- create, so a planted `whisper.exe` there would be run. Found in review,
--- 2026-10-26.
---@param var string
---@return string|nil
local function env_root(var)
  local value = os.getenv(var)
  if type(value) == "string" and value ~= "" then return value end
  return nil
end

---@return string|nil
local function home_root()
  local home = uv.os_homedir()
  if type(home) == "string" and home ~= "" then return home end
  return nil
end

---@class Media.Bin.PythonRoots
---@field programs string|nil  # per-user python.org installs: `<root>/Python3xx/Scripts`
---@field user string|nil      # `pip install --user`: `<root>/Python3xx/Scripts`
---@field store string|nil     # Microsoft Store packages directory
---@field home string|nil      # for `~/.local/bin` and the conda bases

--- The directories the Python search starts from, before any of them is
--- scanned; nil for each whose variable is unset or empty (see `env_root`).
---
--- Public and separate from the scan so the "never a drive-root path" rule is
--- assertable: a root from an empty variable only shows up as a candidate when
--- that directory exists at the drive root, which a test cannot (and must not)
--- arrange.
---@return Media.Bin.PythonRoots
function M.python_roots()
  local localapp = env_root("LOCALAPPDATA")
  local appdata = env_root("APPDATA")
  return {
    programs = localapp and (localapp .. "/Programs/Python") or nil,
    user = appdata and (appdata .. "/Python") or nil,
    store = localapp and (localapp .. "/Packages") or nil,
    home = home_root(),
  }
end

--- Where pip and pipx put a console entry point, for the names in
--- `PYTHON_TOOLS`: an active venv (`$VIRTUAL_ENV`) or conda environment
--- (`$CONDA_PREFIX`) first, then the per-user python.org install
--- (`%LOCALAPPDATA%/Programs/Python/Python3xx/Scripts`), `pip install --user`
--- (`%APPDATA%/Python/Python3xx/Scripts`), and pipx / `pip --user` on Unix
--- (`~/.local/bin`), and last a never-activated conda base (`~/miniconda3`,
--- `~/anaconda3`, `~/miniforge3`). The same PATH problem as winget's: the installer adds the
--- directory to the user PATH, and an editor started before that never sees it.
---
--- Public for the reason `frame.args` is: which paths get probed is the whole
--- decision, and it should be assertable without a Python anywhere.
---@param name string
---@return string[]
function M.python_scripts(name)
  if not PYTHON_TOOLS[name] then return {} end
  local roots = M.python_roots()
  local home = roots.home
  local out = {}

  -- An environment prefix keeps its scripts in `Scripts/` on Windows and in
  -- `bin/` everywhere else; both are probed, a missing one costs one stat.
  ---@param prefix string|nil
  local function add_env(prefix)
    if type(prefix) ~= "string" or prefix == "" then return end
    out[#out + 1] = prefix .. "/Scripts/" .. name .. ".exe"
    out[#out + 1] = prefix .. "/bin/" .. name
  end

  -- First the environment the editor was started in: an active venv or conda
  -- environment is the one the user means, over any global install.
  add_env(env_root("VIRTUAL_ENV"))
  add_env(env_root("CONDA_PREFIX"))

  -- `or false`, not a bare nil: `ipairs` stops at the first nil, so an unset
  -- LOCALAPPDATA would otherwise skip APPDATA's root as well.
  for _, root in ipairs({ roots.programs or false, roots.user or false }) do
    if root then
      -- Newest version last in a sorted listing; tried first.
      local versions = subdirs(root)
      for i = #versions, 1, -1 do
        out[#out + 1] = versions[i] .. "/Scripts/" .. name .. ".exe"
      end
    end
  end
  -- The Microsoft Store Python keeps `pip install --user` scripts under its
  -- package directory: `Packages/PythonSoftwareFoundation.Python.3.xx_<id>/
  -- LocalCache/local-packages/Python3xx/Scripts`.
  local store = roots.store and subdirs(roots.store) or {}
  for i = #store, 1, -1 do
    if store[i]:find("/PythonSoftwareFoundation%.Python%.[^/]*$") then
      local versions = subdirs(store[i] .. "/LocalCache/local-packages")
      for j = #versions, 1, -1 do
        out[#out + 1] = versions[j] .. "/Scripts/" .. name .. ".exe"
      end
    end
  end
  if home then
    out[#out + 1] = home .. "/.local/bin/" .. name .. ".exe"
    out[#out + 1] = home .. "/.local/bin/" .. name
    -- A conda base install that was never activated for this process: the
    -- three installers' default per-user prefixes. Running it unactivated is
    -- what `media.engines.whisper_cli.child_env` makes safe on Windows.
    for _, base in ipairs({ "miniconda3", "anaconda3", "miniforge3" }) do
      add_env(home .. "/" .. base)
    end
  end
  return out
end

--- Every location `find` probes after PATH, in order: the Python locations
--- first — so an active venv really does win over a global install, as its
--- comment always claimed (found in review, 2026-10-26: the installer shims
--- used to come first) — then the installer shim directories.
---
--- Public so the order is assertable.
---@param name string
---@return string[]
function M.candidates(name)
  local out = M.python_scripts(name)
  vim.list_extend(out, well_known(name))
  return out
end

--- The part of the cache key beyond the configured path: for a Python tool,
--- the active environment. A venv selector that sets `VIRTUAL_ENV` after a
--- cached miss must be seen on the next `find`, without `reset()`.
---@param name string
---@return string
local function env_signature(name)
  if not PYTHON_TOOLS[name] then return "" end
  return (os.getenv("VIRTUAL_ENV") or "") .. "\0" .. (os.getenv("CONDA_PREFIX") or "")
end

---@class Media.Bin.CacheEntry
---@field cfg string|nil     # `config.get().bin[name]` at the time this was resolved
---@field env string         # `env_signature(name)` at that time
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
  local env = env_signature(name)

  local cached = resolved[name]
  if cached ~= nil and cached.cfg == configured and cached.env == env then
    return cached.val or nil
  end

  ---@param val string|false
  local function remember(val)
    resolved[name] = { cfg = configured, env = env, val = val }
  end

  if type(configured) == "string" and configured ~= "" then
    -- An explicit path is honoured as given, including when it does not exist:
    -- the error the user then gets names their own setting, which is a better
    -- place to start looking than "ffmpeg not found".
    remember(configured)
    return configured
  end

  local ok, executable = pcall(require, "lib.nvim.cross.executable")
  if (ok and executable.exists(name)) or (not ok and vim.fn.executable(name) == 1) then
    remember(name)
    return name
  end

  for _, candidate in ipairs(M.candidates(name)) do
    if is_file(candidate) then
      remember(candidate)
      return candidate
    end
  end

  remember(false)
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
