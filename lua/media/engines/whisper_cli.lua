---@module 'media.engines.whisper_cli'
---@brief What the Python Whisper CLIs have in common: one run, one JSON file.
---@description
--- openai-whisper's `whisper` and faster-whisper's `whisper-ctranslate2` are
--- the same program from the outside: `<bin> <audio> --output_format json
--- --output_dir <dir>`, a `<audio basename>.json` holding `{ text, segments =
--- [{ start, end, text }], language }` in seconds, and — both of them — a
--- per-file failure that is caught, reported on a stream and answered with
--- exit code 0. This module is that shared half: the private output
--- directory, the process, reading the JSON back, the cleanup and the cancel.
--- Each engine keeps what differs: its argv, its model names and download
--- check, and how its failure message is worded.
---
--- Not an engine (it has no `id`, and `media.engines` does not register it).

local uv = vim.uv or vim.loop

local M = {}

--- The JSON both CLIs write, as a `Media.Transcript`.
---@param doc table decoded JSON
---@param engine_id string
---@param model string|nil
---@return Media.Transcript
function M.to_transcript(doc, engine_id, model)
  local segments = {}
  local entries = type(doc.segments) == "table" and doc.segments or {}
  for i, entry in ipairs(entries) do
    segments[i] = {
      s = tonumber(entry.start) or 0,
      e = tonumber(entry["end"]) or 0,
      text = type(entry.text) == "string" and vim.trim(entry.text) or "",
    }
  end

  return {
    engine = engine_id,
    model = model,
    lang = type(doc.language) == "string" and doc.language or nil,
    duration = nil,
    segments = segments,
    text = require("media.core.segments").to_text(segments),
  }
end

--- UTF-8 stdio for a Python child, so a non-ASCII file name in its own
--- messages cannot crash the console encoding on Windows — plus, with
--- `with_ffmpeg`, ffmpeg's directory in front of PATH when `core.bin`
--- resolved it to an absolute path (openai-whisper decodes through ffmpeg
--- from PATH; faster-whisper does not need it).
---@param with_ffmpeg boolean
---@return table<string, string>
function M.child_env(with_ffmpeg)
  local env = { PYTHONIOENCODING = "utf-8", PYTHONUTF8 = "1" }
  if with_ffmpeg then
    local ffmpeg = require("media.core.bin").find("ffmpeg")
    if ffmpeg and ffmpeg:find("[/\\]") then
      local dir = vim.fs.dirname(ffmpeg)
      local sep = vim.fn.has("win32") == 1 and ";" or ":"
      env.PATH = dir .. sep .. (os.getenv("PATH") or "")
    end
  end
  return env
end

---@param dir string
local function remove_dir(dir)
  local handle = uv.fs_scandir(dir)
  if handle then
    while true do
      local entry = uv.fs_scandir_next(handle)
      if not entry then break end
      os.remove(dir .. "/" .. entry)
    end
  end
  uv.fs_rmdir(dir)
end

--- A job that fails with `err` on the next tick — the "binary or model
--- missing" exit, which must still call back on the main loop and still be
--- cancellable like a real run.
---@param err string
---@param callback fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Engine.Job
function M.fail(err, callback)
  local cancelled = false
  vim.schedule(function()
    if not cancelled then callback(nil, err) end
  end)
  return {
    cancel = function()
      cancelled = true
    end,
  }
end

---@class Media.WhisperCli.Spec
---@field wav_path string
---@field argv fun(out_dir: string): string[]  # the full argv, given the private output directory
---@field env table<string, string>|nil
---@field label string  # the binary's name, for the fallback messages
---@field failure_reason fun(stdout: string|nil, stderr: string|nil): string|nil
---@field parse fun(doc: table): Media.Transcript

--- Run one transcription and hand back a cancellable job.
---
--- A private directory per call, for the reason `whisper_cpp` uses a private
--- prefix: two concurrent runs on the same WAV would otherwise write, read
--- and delete the same `<basename>.json`. Removed on every exit path,
--- including after a cancel (the killed process still calls back).
---@param spec Media.WhisperCli.Spec
---@param callback fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Engine.Job
function M.run(spec, callback)
  local cfg = require("media.config").get().transcribe

  local cancelled = false
  ---@type vim.SystemObj|nil
  local proc = nil
  local job = {
    cancel = function()
      cancelled = true
      if proc then
        pcall(function()
          require("media.core.proc").stop(proc)
        end)
        proc = nil
      end
    end,
  }

  ---@param transcript Media.Transcript|nil
  ---@param err string|nil
  local function finish(transcript, err)
    if cancelled then return end
    callback(transcript, err)
  end

  local out_dir = vim.fn.tempname()
  vim.fn.mkdir(out_dir, "p")
  local stem = vim.fn.fnamemodify(spec.wav_path, ":t:r")
  local json_path = out_dir .. "/" .. stem .. ".json"

  -- `0` means "no timeout", passed as `nil` — see `whisper_cpp.transcribe`.
  local timeout = (cfg.timeout_ms and cfg.timeout_ms > 0) and cfg.timeout_ms or nil

  proc = vim.system(
    spec.argv(out_dir),
    { text = true, timeout = timeout, env = spec.env },
    function(result)
      proc = nil
      local fd = io.open(json_path, "r")
      if result.code ~= 0 or not fd then
        if fd then fd:close() end
        remove_dir(out_dir)
        local reason = spec.failure_reason(result.stdout, result.stderr)
        if not reason then
          reason = result.code ~= 0
              and ("%s exited with %s"):format(spec.label, tostring(result.code))
            or ("%s wrote no JSON: %s"):format(spec.label, json_path)
        end
        finish(nil, reason)
        return
      end
      local content = fd:read("*a")
      fd:close()
      remove_dir(out_dir)

      local ok, doc = pcall(vim.json.decode, content)
      if not ok or type(doc) ~= "table" then
        finish(nil, spec.label .. "'s JSON output could not be read")
        return
      end

      finish(spec.parse(doc), nil)
    end
  )

  return job
end

return M
