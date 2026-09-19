---@module 'media.hub.scan'
---@brief Which files are here, and whether their text is missing, stale or fine.
---@description
--- The dashboard's input (ROADMAP.md, "The hub"). Three words of scope, one
--- walk, and a three-way answer per file.
---
--- **`cfile` / `cwd` / `path=<dir>` are the ecosystem's three words**, the same
--- ones `images.browse.roots()` and `language.scope` already use, with the same
--- three meanings. Resolved here rather than by calling images.nvim's copy,
--- because a dashboard that cannot say what directory it is looking at without
--- an optional dependency installed is not soft about that dependency at all.
---
--- **The walk is `images.browse.walk`'s shape**: iterative `fs_scandir` rather
--- than recursion (a deep tree must not be a stack depth), an exclusion set, and
--- a hard cap on visited entries so a scan accidentally started in a home
--- directory stops quietly with what it found instead of hanging the editor.
---
--- **Nothing here starts a process.** Not one `ffprobe`, not one `pdfinfo`. A
--- directory of five hundred files would otherwise be five hundred processes
--- before a single row is drawn, and the dashboard's own row format needs the
--- per-file detail (`14:32`, `1920x1080`, `24 pages`) only for the rows on
--- screen. `media.probed()` answers that from cache, synchronously and
--- without blocking, for whatever has already been probed; the rest is filled
--- in by the view, lazily, or not at all.
---
--- **"stale" stays a distinct state from "missing", which is the whole point.**
--- The precedent this rule comes from — `casedesk.nvim`'s `ocr.is_stale`, and
--- `media.output.sidecar.is_stale` — answers a *boolean*, and both callers are
--- right to: they are deciding whether to re-run, and "missing" and "stale"
--- both mean yes. A dashboard is not deciding, it is reporting, and for a
--- reader the two could not be less alike. Missing is a job not yet done.
--- Stale is a file on disk that answers questions about a version of the source
--- that no longer exists — the state that silently produces wrong answers, and
--- the only reason this column is worth a dashboard.

local M = {}

local uv = vim.uv or vim.loop

---@internal
--- `~`/env expansion only -- never Vim's filename specials or a shell command
--- substitution, both of which `vim.fn.expand()` performs on a backtick span
--- or a `%`/`#`/`<cfile>` argument (SEC-34): `arg` here is the `path=<dir>`
--- value off a `:Media dashboard` command line. `lib.nvim.cross.fs.expand_path`
--- when present, a small equivalent when not -- this plugin's soft dependency
--- on lib.nvim holds everywhere else, and a dashboard that only resolves its
--- `path=` scope with lib.nvim installed would be a new, undocumented one.
---@param path string
---@return string
local function expand_path(path)
  local ok, expand = pcall(require, "lib.nvim.cross.fs.expand_path")
  if ok then return expand(path) end
  if path:sub(1, 1) == "~" then
    local home = uv.os_homedir()
    if home then path = home .. path:sub(2) end
  end
  path = path:gsub("%%([%w_]+)%%", function(name)
    return vim.env[name] or ("%" .. name .. "%")
  end)
  return (path:gsub("%$([%w_]+)", function(name)
    return vim.env[name] or ("$" .. name)
  end))
end

--- Directory names never descended into, whatever the configuration says.
---
--- `node_modules` is named in the roadmap itself, and for the obvious reason:
--- it is where an entry cap goes to die. `.git` matches `images.browse`'s own
--- always-excluded set.
---@type table<string, boolean>
local ALWAYS_EXCLUDE = {
  [".git"] = true,
  ["node_modules"] = true,
}

--- Where a scan starts.
---
--- Deliberately the same three words as `images.browse.roots()` and
--- `language.scope`, with the same three meanings — one vocabulary across every
--- plugin here, so a reader who has learned `cfile` once has learned it
--- everywhere.
---@alias Media.Hub.Scope "cfile"|"cwd"|"path"

--- The state of one file's text.
---
--- `"none"` is for a kind that has no text operation at all, and is not the
--- same as `"missing"`: a `.lua` file is not waiting for anything.
---@alias Media.Hub.Status "ok"|"stale"|"missing"|"none"

--- One row of the dashboard, before anything has been drawn or probed.
---@class Media.Hub.Entry
---@field path string      # absolute
---@field name string      # relative to the scan root — what a row shows
---@field kind Media.Hub.Kind
---@field status Media.Hub.Status
---@field sidecar string|nil  # the file `status` is about, when the kind has one
---@field age integer|nil     # seconds since the sidecar was written, for "3 days old"

--- Resolve a scope to an absolute directory.
---@param scope Media.Hub.Scope|nil  # default "cwd"
---@param arg string|nil  # the directory, for scope "path"
---@return string|nil root
---@return string|nil err
function M.root(scope, arg)
  scope = scope or "cwd"

  if scope == "cwd" then return vim.fs.normalize(uv.cwd() or vim.fn.getcwd()) end

  if scope == "cfile" then
    -- The current buffer's *directory*, as in `images.browse.roots()`: the
    -- question a dashboard answers is "what else is next to this", and a scope
    -- resolving to a single file would make the dashboard a one-row list.
    local name = vim.api.nvim_buf_get_name(0)
    if name == "" then return nil, "the current buffer has no file path" end
    return vim.fs.normalize(vim.fn.fnamemodify(name, ":p:h"))
  end

  if scope == "path" then
    if not arg or arg == "" then
      return nil, "the `path` scope needs a directory: :Media dashboard path=<dir>"
    end
    local expanded = vim.fn.fnamemodify(expand_path(arg), ":p")
    if vim.fn.isdirectory(expanded) == 0 then return nil, "not a directory: " .. arg end
    return vim.fs.normalize(expanded)
  end

  return nil, ("unknown scope: %s (expected cfile, cwd or path=<dir>)"):format(tostring(scope))
end

--- Every file below `root`, breadth-first and iteratively.
---
--- Pure and public for the reason every `args` function in this plugin is: the
--- decisions worth asserting — what is excluded, that the cap holds, that
--- sidecars do not list themselves — are invisible in a rendered dashboard and
--- need no filesystem of any size to check.
---
--- Returns paths sorted, and the cap is a quiet stop rather than an error: what
--- was found before it is still a useful answer, and a dashboard refusing to
--- draw because a directory was large would be the worse failure.
---@param root string absolute
---@param exclude string[]|nil  # additional directory names to skip
---@param max_entries integer
---@return string[] paths
---@return string[] unreadable  # directories `fs_scandir` could not open -- permission, a dropped mount, a junction `isdirectory` accepts but this refuses. Distinct from a directory that opened and was simply empty (ERR-11).
function M.walk(root, exclude, max_entries)
  local exclude_set = vim.deepcopy(ALWAYS_EXCLUDE)
  for _, name in ipairs(exclude or {}) do
    exclude_set[name] = true
  end

  local kinds = require("media.hub.kinds")
  local found = {}
  local unreadable = {}
  local visited = 0
  local stack = { root }

  while #stack > 0 do
    local dir = table.remove(stack)
    local handle = uv.fs_scandir(dir)
    if not handle then
      unreadable[#unreadable + 1] = dir
    else
      while true do
        local name, entry_kind = uv.fs_scandir_next(handle)
        if not name then break end
        visited = visited + 1
        if visited > max_entries then
          table.sort(found)
          return found, unreadable
        end
        local full = dir .. "/" .. name

        -- **A symlink to a file is resolved; one to a directory is not.**
        --
        -- `fs_scandir_next` reports `"link"`, and treating that as neither a
        -- file nor a directory drops it silently — which for a media library
        -- is the common case rather than an edge one: a directory of symlinks
        -- into a NAS scanned as empty. One extra `fs_stat`, and only for the
        -- entries that are actually links. `images.browse.walk` still has the
        -- gap this closes. Found in review, 2026-09-17.
        --
        -- Descending into a linked *directory* is the other half, and it is
        -- deliberately not done: `a/here -> ..` is a cycle, and the only thing
        -- standing between it and a hang would be `max_entries` — which bounds
        -- the damage but not the nonsense, since everything it found on the way
        -- would be the same files under twenty made-up paths. Following files
        -- gets the case people actually have without that.
        if entry_kind == "link" then
          local target = uv.fs_stat(full)
          entry_kind = (target and target.type == "file") and "file" or nil
        end

        if entry_kind == "directory" then
          if not exclude_set[name] then stack[#stack + 1] = full end
        elseif entry_kind == "file" then
          -- A sidecar is this hub's own output. Listed, it would be offered
          -- for extraction on the next scan — a `.transcript.md` is, after
          -- all, a perfectly ordinary markdown file.
          if not kinds.is_sidecar(name) then found[#found + 1] = full end
        end
      end
    end
  end

  table.sort(found)
  return found, unreadable
end

--- The state of `path`'s text: is the sidecar there, and is it still true?
---
--- Three answers where the precedent gives two, and the middle one is why (see
--- the module header). The comparison is mtime against mtime, exactly
--- `casedesk.nvim`'s `ocr.is_stale` rule: a source edited after its sidecar was
--- written has a sidecar describing a version that no longer exists.
---
--- A source that cannot be stat'ed at all answers `"ok"` rather than `"stale"`:
--- the file was there a moment ago when the walk found it, so this is a race
--- with something else deleting it, and inventing a warning about a file that
--- is gone helps nobody.
---@param path string
---@param kind Media.Hub.Kind|nil
---@return Media.Hub.Status
---@return string|nil sidecar
---@return integer|nil age  # seconds since the sidecar was written
function M.status(path, kind)
  local sidecar = require("media.hub.kinds").sidecar(path, kind)
  if not sidecar then return "none", nil, nil end

  local side_stat = uv.fs_stat(sidecar)
  if not side_stat then return "missing", sidecar, nil end

  local written = side_stat.mtime and side_stat.mtime.sec or 0
  local age = math.max(0, os.time() - written)

  local source = uv.fs_stat(path)
  if not source then return "ok", sidecar, age end

  local changed = source.mtime and source.mtime.sec or 0
  if changed > written then return "stale", sidecar, age end
  return "ok", sidecar, age
end

--- Everything under `scope`, as dashboard rows.
---
--- Synchronous, and that is a deliberate bound rather than an oversight: the
--- whole of this is `fs_scandir` plus one `fs_stat` per file with a sidecar,
--- which is the same order of work a file tree does to draw itself. The
--- expensive half — probing each file for its duration, its dimensions, its
--- page count — is exactly what this does *not* do; see the module header.
---@param scope Media.Hub.Scope|nil
---@param arg string|nil
---@return Media.Hub.Entry[]|nil entries
---@return string|nil err
function M.scan(scope, arg)
  local root, err = M.root(scope, arg)
  if not root then return nil, err end

  local cfg = require("media.config").get().hub
  local kinds = require("media.hub.kinds")

  local walked, unreadable = M.walk(root, cfg.exclude, cfg.max_entries)

  local entries = {}
  for _, path in ipairs(walked) do
    local kind = kinds.of(path)
    if kind ~= "other" then
      local status, sidecar, age = M.status(path, kind)
      entries[#entries + 1] = {
        path = path,
        name = M.relative(path, root),
        kind = kind,
        status = status,
        sidecar = sidecar,
        age = age,
      }
    end
  end

  -- "Nothing found" and "could not look" must not collapse into the same
  -- silent empty list (ERR-11): a permission-denied share or a dropped mount
  -- yields the same zero `entries` a genuinely empty directory does, and only
  -- one of the two is the truth "no images, PDFs, audio or video here" tells.
  if #unreadable > 0 then
    return entries,
      ("%d director%s could not be read, including %s"):format(
        #unreadable,
        #unreadable == 1 and "y" or "ies",
        unreadable[1]
      )
  end

  return entries, nil
end

--- `path` as a row shows it: relative to the scan root, forward slashes.
---
--- Relative because the root is stated once above the list and repeating it on
--- every row buys nothing but width — the same reason a file tree does not
--- print the project directory in front of each file.
---@param path string
---@param root string
---@return string
function M.relative(path, root)
  local prefix = root:gsub("/+$", "") .. "/"
  if path:sub(1, #prefix) == prefix then return path:sub(#prefix + 1) end
  return path
end

return M
