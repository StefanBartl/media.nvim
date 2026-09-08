---@module 'media.core.audio'
---@brief Sound for a played video — an audio-only mpv, talked to over its JSON IPC.
---@description
--- **Why this is mpv and not a decoder.** The naive design has the picture
--- lead: a Lua timer ticks, draws a frame, ticks again. Sound then needs its
--- own clock synchronised to that timer's, and a timer in an editor process is
--- not a clock a listener would forgive drifting from. The design this module
--- follows instead is a reversal: there is already a process with a perfect
--- clock in the system, the audio player, because a sound card plays samples
--- at exactly one rate. So the sound leads and the picture follows — `mpv
--- --no-video` plays the file, and the caller asks it *where it is* rather
--- than counting. `hover.preview.playback` polls `time_pos` once per paint and
--- derives the frame to show from the answer, not from a tick count. Drawn
--- late, a frame is simply the *next* one when the answer catches up — it
--- never accumulates the way a free-running timer racing a free-running
--- player would.
---
--- `ffplay` cannot do this: it never reports its position. mpv can, over the
--- same kind of socket `--input-ipc-server` opens for remote control, and
--- `media.core.play` already knows mpv as a `player` option — this is the
--- same binary, asked to do less.
---
--- **Why not FFI or a bundled decoder.** LuaJIT could decode audio in-process,
--- but decoding in the editor's own event loop is exactly the trap
--- `media.nvim` is built with `vim.system` to avoid — a video-length function
--- call would freeze every keystroke for its length. A second process is not
--- a workaround here, it is the point.
---
--- **Fails soft, always.** No mpv on PATH, the IPC socket never comes up, the
--- process dies mid-play: every one of those calls the caller back with `nil`
--- and a reason, never raises, and the caller's answer is always "play
--- silently, the way it already did" — never an error the reader sees.

local M = {}

local uv = vim.uv or vim.loop

--- Find mpv the way `ffmpeg`/`ffprobe` are found — PATH first, then the
--- winget/scoop/chocolatey shim locations `media.core.bin` already knows,
--- with `bin.mpv` in the configuration as the escape hatch.
---@return string|nil
function M.find_mpv()
  return require("media.core.bin").find("mpv")
end

--- Whether sound can be attempted at all right now.
---@return boolean
function M.available()
  return M.find_mpv() ~= nil
end

--- The argv for one mpv audio-only run.
---
--- Pure and public for the same reason `frames.args` is: `--no-video` before
--- the file and `--start` only when there is somewhere to start from are
--- decisions invisible in what comes out of the speakers until they are
--- wrong, and asserting them should not need mpv installed.
---@param spec { mpv: string, path: string, sock: string, at: number|nil }
---@return string[]
function M.args(spec)
  local argv = {
    spec.mpv,
    "--no-video",
    "--no-terminal",
    "--idle=no",
    "--keep-open=no",
    ("--input-ipc-server=%s"):format(spec.sock),
  }
  if type(spec.at) == "number" and spec.at > 0 then
    argv[#argv + 1] = ("--start=%s"):format(tostring(spec.at))
  end
  argv[#argv + 1] = spec.path
  return argv
end

---@internal
--- A socket path this session has not used yet.
---
--- Windows names a pipe; everywhere else this is a filesystem path for a Unix
--- domain socket, placed next to the rendered stills — `media.core.cache`
--- already made that directory and keeps it writable.
---@return string
local function socket_path()
  local tag = ("%d-%d"):format(uv.os_getpid(), math.random(100000, 999999))
  if vim.fn.has("win32") == 1 then return "\\\\.\\pipe\\media.nvim-" .. tag end
  return require("media.core.cache").dir() .. "/mpv-" .. tag .. ".sock"
end

---@internal
--- Wrap a connected pipe into the handle `M.start` hands back.
---
--- mpv's JSON IPC is line-delimited: every request and every reply is one
--- JSON object followed by `\n`, and replies are matched to requests by
--- `request_id` — there is no other way to tell a reply from the unrelated
--- events mpv also writes to the same socket (property changes, log lines),
--- which this ignores by simply never subscribing to any.
---@param pipe uv.uv_pipe_t
---@param proc vim.SystemObj
---@return Media.Audio.Handle
local function wrap(pipe, proc)
  local next_id = 0
  ---@type table<integer, fun(msg: table): nil>
  local pending = {}
  local buf = ""
  local stopped = false

  pipe:read_start(function(err, chunk)
    if stopped or err or not chunk then return end
    buf = buf .. chunk
    while true do
      local nl = buf:find("\n", 1, true)
      if not nl then break end
      local line = buf:sub(1, nl - 1)
      buf = buf:sub(nl + 1)
      if line ~= "" then
        local ok, msg = pcall(vim.json.decode, line)
        if ok and type(msg) == "table" and msg.request_id and pending[msg.request_id] then
          local cb = pending[msg.request_id]
          pending[msg.request_id] = nil
          vim.schedule(function()
            cb(msg)
          end)
        end
      end
    end
  end)

  ---@param payload table
  local function send(payload)
    if stopped then return end
    pcall(function()
      pipe:write(vim.json.encode(payload) .. "\n")
    end)
  end

  ---@param command (string|number|boolean)[]
  ---@param callback fun(msg: table): nil
  local function request(command, callback)
    next_id = next_id + 1
    pending[next_id] = callback
    send({ command = command, request_id = next_id })
  end

  return {
    pause = function()
      send({ command = { "set_property", "pause", true } })
    end,
    resume = function()
      send({ command = { "set_property", "pause", false } })
    end,
    seek = function(seconds)
      send({ command = { "seek", seconds, "absolute" } })
    end,
    time_pos = function(callback)
      if stopped then
        callback(nil)
        return
      end
      request({ "get_property", "time-pos" }, function(msg)
        callback(msg.error == "success" and type(msg.data) == "number" and msg.data or nil)
      end)
    end,
    stop = function()
      if stopped then return end
      stopped = true
      pending = {}
      pcall(function()
        pipe:read_stop()
      end)
      pcall(function()
        pipe:close()
      end)
      -- Through `media.core.proc`, never `proc:kill` directly: on Windows the
      -- pid this holds is a `mpv.COM` wrapper and the player is its child, so
      -- a signal to it is reported as delivered and stops nothing. That module
      -- carries the measurement.
      require("media.core.proc").stop(proc)
    end,
  }
end

--- Start mpv on `path`, audio only, from `opts.at` seconds in — and hand back
--- a handle once its IPC socket answers.
---
--- The socket is not there the instant the process is: mpv creates it after
--- its own startup, so this retries the connection rather than failing on the
--- first attempt. Two seconds of retrying (40 tries, 50 ms apart) is well past
--- what mpv takes to open a socket on this machine and short enough that a
--- reader who pressed play notices nothing before either sound starts or the
--- caller is told to carry on without it.
---@param path string
---@param opts Media.AudioOpts|nil
---@param callback fun(handle: Media.Audio.Handle|nil, err: string|nil): nil
---@return nil
function M.start(path, opts, callback)
  opts = opts or {}
  local mpv = M.find_mpv()
  if not mpv then
    callback(nil, "mpv not found — audio disabled, playback stays silent")
    return
  end

  local sock = socket_path()
  local argv = M.args({ mpv = mpv, path = path, sock = sock, at = opts.at })

  -- Not `detach`, and not awaited — the same two decisions `media.core.play`
  -- makes, and its module header explains why: `detach` never starts a
  -- console program on Windows at all, and waiting would block the editor for
  -- the length of the file.
  local proc = vim.system(argv, {})

  local attempts = 0
  local given_up = false

  -- **A fresh pipe per attempt, and that is the fix rather than the style.**
  -- Retrying `connect` on a `uv_pipe_t` that has already failed once returns
  -- `EBUSY` on Windows, forever: the handle is spent, not idle. Reusing one
  -- meant the first attempt failed with the honest "the socket is not there
  -- yet" and all thirty-nine after it failed with EBUSY -- so the handle never
  -- came up at all, `state.audio` stayed nil, and mpv played on with nothing
  -- able to pause, seek or stop it. Measured 2026-09-08.
  local function try_connect()
    if given_up then return end
    attempts = attempts + 1

    local pipe = uv.new_pipe(false)

    ---@param reason string
    local function retry(reason)
      pcall(function()
        pipe:close()
      end)
      if attempts >= 40 then
        given_up = true
        require("media.core.proc").stop(proc)
        vim.schedule(function()
          callback(nil, "mpv's IPC socket never came up: " .. reason)
        end)
        return
      end
      local timer = uv.new_timer()
      timer:start(50, 0, function()
        timer:stop()
        timer:close()
        try_connect()
      end)
    end

    local ok, err = pcall(function()
      pipe:connect(sock, function(cerr)
        if given_up then return end
        if cerr then
          retry(tostring(cerr))
          return
        end
        vim.schedule(function()
          callback(wrap(pipe, proc), nil)
        end)
      end)
    end)

    -- `connect` can throw rather than call back -- a malformed pipe name, a
    -- handle libuv refuses. Retrying is right either way; the distinction
    -- matters only in the message.
    if not ok then retry(tostring(err)) end
  end

  try_connect()
end

return M
