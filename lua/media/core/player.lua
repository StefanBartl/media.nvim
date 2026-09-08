---@module 'media.core.player'
---@brief A real mpv window, opened on a file and owned by its caller — video and
--- sound, with a handle that stops the whole process tree.
---@description
--- **Why a window and not the in-terminal renderer.** A consumer
--- (`hover.nvim`) can already turn a video into moving block graphics inside a
--- float: `media.frames` samples a run of stills and `images.blocks` paints
--- them. It works, and on a fast terminal it is smooth — but painting a
--- float-sized canvas twelve times a second means Neovim redraws that region
--- twelve times a second, and on Windows/WezTerm that was measured at roughly
--- one repaint per second however the paint was written (buffer lines, then
--- extmarks, then overlay virtual text — three rewrites, same result). The
--- picture is the editor's redraw, and the editor's redraw is the ceiling.
---
--- mpv's own window has no such ceiling. It decodes, scales, syncs sound to the
--- picture and draws with the GPU, exactly as it does for any other file — this
--- module only starts it pointed at the right file and offset, and keeps the
--- handle needed to stop it again.
---
--- **This is `media.core.audio` with the video left on.** That module runs
--- `mpv --no-video` under a JSON-IPC socket so a caller can poll its clock;
--- this one wants the picture and needs no clock back, so there is no socket —
--- just the `vim.system` process handle and `media.core.proc` to end the tree.
---
--- **`detach` is not used, and must not be** — the reason is in
--- `media.core.play`'s header: on Windows `jobstart(argv, { detach = true })`
--- never starts a console program at all, and `mpv` resolves through a `.COM`
--- console wrapper. `vim.system(argv, {})` unawaited is the form that works.
---
--- **The window may open behind the terminal.** Windows only lets a process
--- foreground a window if it (or its ancestor) already owns the foreground,
--- which inside a terminal is the terminal host and not `nvim.exe`. `--ontop`
--- keeps the window visible above the terminal regardless of focus, which is
--- why it defaults on; mpv's own `--focus-on=open` does the rest where the OS
--- allows it. Under a GUI Neovim the window comes to the front by itself.
---
--- **Fails soft.** No mpv on PATH returns `nil` and a reason, never raises —
--- the caller's answer is "show the still and say why", the same contract the
--- rest of this plugin keeps.

local M = {}

--- Whether a windowed player can be started at all right now — i.e. mpv is
--- resolvable. Shares `media.core.audio`'s resolution (PATH, then the
--- winget/scoop/chocolatey locations `media.core.bin` knows, then `bin.mpv`).
---@return boolean
function M.available()
  return require("media.core.audio").find_mpv() ~= nil
end

--- Every window this session has started and not yet stopped.
---
--- mpv is a real OS process outside Neovim's lifetime, and a window opened
--- right before `:qa` would keep playing on its own — the same failure
--- `media.core.audio` guards against. A consumer that ties a window to some UI
--- element of its own (a closing hover) still calls `handle.stop` on that path;
--- this list is the backstop for the exit that runs none of those.
---@type table<Media.Player.Handle, true>
local live = setmetatable({}, { __mode = "k" })

--- Whether the `VimLeavePre` sweep has been installed this session.
local hooked = false

---@return nil
local function hook_cleanup()
  if hooked then return end
  hooked = true
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("MediaNvimPlayer", { clear = true }),
    desc = "media.nvim: stop any mpv window still open at exit",
    callback = function()
      for handle in pairs(live) do
        pcall(handle.stop)
      end
    end,
  })
end

--- The windows started and not yet stopped, for `:checkhealth media` and tests.
---@return integer
function M.live_count()
  local n = 0
  for _ in pairs(live) do
    n = n + 1
  end
  return n
end

--- The argv for one windowed mpv run.
---
--- Pure and public for the same reason `media.core.audio.args` is: the flags
--- that matter here are invisible in the running window until one is wrong, and
--- asserting them should not need mpv installed.
---
--- - `--force-window=immediate` puts a window on screen before the first frame
---   is decoded, so a slow seek does not look like nothing happened.
--- - `--keep-open=no` closes the window at end of file rather than freezing on
---   the last frame — a player, not a viewer.
--- - `--no-terminal` because this mpv has no console of its own; without it mpv
---   tries to drive one and logs into the void.
--- - `--start` only when there is a real offset: `--start=0` is harmless but
---   noise, and a caller that resolved no offset passes `nil`. mpv's own
---   `--start` grammar is honoured, so a percentage (`"50%"`) or an ffmpeg
---   timestamp (`"00:01:23"`) passes straight through — this does not resolve
---   them, mpv does.
--- - `--title` names the window for the file, so a taskbar with three of them
---   is legible.
---@param spec { mpv: string, path: string, at?: number|string, autofit?: string, ontop?: boolean, mute?: boolean, extra?: string[] }
---@return string[]
function M.args(spec)
  local argv = {
    spec.mpv,
    "--force-window=immediate",
    "--no-terminal",
    "--idle=no",
    "--keep-open=no",
    "--title=media.nvim — ${filename}",
  }
  if spec.ontop ~= false then argv[#argv + 1] = "--ontop" end
  if type(spec.autofit) == "string" and spec.autofit ~= "" then
    -- `-larger`: shrink an oversized video to fit, never enlarge a small one
    -- past its own pixels, where scaling would only add blur.
    argv[#argv + 1] = ("--autofit-larger=%s"):format(spec.autofit)
    -- Centre the window rather than let the platform place it at a corner.
    argv[#argv + 1] = "--geometry=50%:50%"
  end
  if spec.mute then argv[#argv + 1] = "--mute=yes" end
  local at = spec.at
  if (type(at) == "number" and at > 0) or (type(at) == "string" and at ~= "" and at ~= "0") then
    argv[#argv + 1] = ("--start=%s"):format(tostring(at))
  end
  for _, arg in ipairs(spec.extra or {}) do
    argv[#argv + 1] = arg
  end
  -- Last, and after `--`, so a file whose name begins with `-` is still a file.
  argv[#argv + 1] = "--"
  argv[#argv + 1] = spec.path
  return argv
end

--- Start mpv on `path` in its own window, from `opts.at` seconds in.
---
--- Synchronous to start (the process is spawned and not awaited) and returns a
--- handle immediately — there is no socket to wait for, unlike `media.audio`.
--- `stop()` is idempotent and ends the whole tree, which on Windows is the only
--- thing that actually stops mpv (see `media.core.proc`).
---@param path string
---@param opts Media.PlayerOpts|nil
---@return Media.Player.Handle|nil handle
---@return string|nil err
function M.start(path, opts)
  if type(path) ~= "string" or path == "" then return nil, "no path given" end
  opts = opts or {}

  local mpv = require("media.core.audio").find_mpv()
  if not mpv then return nil, "mpv not found — install it, or set `bin.mpv`" end

  local cfg = require("media.config").get()
  local window = type(cfg.window) == "table" and cfg.window or {}

  local argv = M.args({
    mpv = mpv,
    path = path,
    at = (type(opts.at) == "number" or type(opts.at) == "string") and opts.at or nil,
    autofit = opts.autofit ~= nil and opts.autofit or window.autofit,
    ontop = opts.ontop ~= nil and opts.ontop or window.ontop,
    mute = opts.mute == true,
    extra = type(window.args) == "table" and window.args or nil,
  })

  local stopped = false
  ---@type Media.Player.Handle|nil
  local handle

  -- Not detached, and not awaited — the two decisions `media.core.play` and
  -- `media.core.audio` both make, for the reasons their headers give. The
  -- third argument is a completion callback, not a wait: it runs on libuv's
  -- thread when mpv exits *on its own* (end of file, the close button, mpv's
  -- own `q`), so the handle can drop out of `live` without a poll loop. It
  -- must `vim.schedule` before touching anything — the callback thread is not
  -- the main loop.
  local proc = vim.system(argv, {}, function()
    vim.schedule(function()
      if handle then live[handle] = nil end
    end)
  end)

  handle = {
    proc = proc,
    stopped = function()
      return stopped
    end,
    stop = function()
      if stopped then return end
      stopped = true
      live[handle] = nil
      -- Through `media.core.proc`: on Windows the pid here is the `mpv.COM`
      -- wrapper and the real player is its child, so a signal to it stops
      -- nothing. That module carries the measurement.
      require("media.core.proc").stop(proc)
    end,
  }

  live[handle] = true
  hook_cleanup()

  return handle, nil
end

return M
