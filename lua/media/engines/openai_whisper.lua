---@module 'media.engines.openai_whisper'
---@brief Local transcription via OpenAI's reference `whisper` CLI (PyTorch).
---@description
--- The second engine (ROADMAP.md's candidate list: "openai_whisper, local,
--- reference implementation"). What `pip install openai-whisper` installs:
--- a Python console entry point `whisper`, which takes a model *name*
--- (`tiny` … `large-v3`, `turbo`) rather than a file, and fetches that
--- model into its own cache on first use.
---
--- Shells out to `whisper <wav> --model <m> --output_format json
--- --output_dir <dir> --verbose False [--language] [--task translate]` and
--- reads `<dir>/<wav basename>.json` back from disk, for the reason
--- `whisper_cpp` does: the file carries the timestamped segments in a stable
--- shape, stdout does not.
---
--- **Read from the installed source, 20250625** (`whisper/transcribe.py`'s
--- `cli`, `whisper/utils.py`'s `ResultWriter`): the JSON is `{ text,
--- segments = [{ start, end, text, … }], language }`, times in **seconds**
--- (whisper.cpp's are milliseconds); the output file is named after the
--- input's basename with its extension replaced. And like `whisper-cli`, the
--- CLI **exits 0 on a per-file failure**: it catches the exception, prints a
--- traceback and `Skipping <file> due to <Error>: <msg>`, and moves on — so
--- the missing JSON, not the exit code, is the test; see `M.failure_reason`.
---
--- **Model downloads.** ROADMAP.md's "Risks" rule is that this plugin never
--- fetches a model unasked, and whisper fetches one silently the first time
--- a name is used (`turbo` is 1.6 GB). So before a run the model file is
--- looked for in whisper's cache; a missing one is an error naming the
--- download, unless `transcribe.openai_whisper.allow_download = true` says
--- the user has agreed to it once and for all.
---
--- **ffmpeg on the child's PATH.** whisper decodes every input — the WAV
--- `media.core.normalize` already produced included — by running `ffmpeg`
--- from PATH. `core.bin` may have found ffmpeg somewhere PATH does not
--- reach (the winget/scoop shim case it exists for), so its directory is
--- prepended to the child's PATH.

local uv = vim.uv or vim.loop

--- Declared as a class, like `Media.Engine.WhisperCpp`, so the methods below
--- the literal count as implementing `Media.Engine`.
---@class Media.Engine.OpenAIWhisper : Media.Engine
local M = {
  id = "openai_whisper",
  name = "OpenAI Whisper (local, PyTorch)",
  capabilities = {
    local_ = true,
    remote = false,
    segments = true,
    translate_to_en = true,
  },
}

--- The CLI's own default model, used when neither the call nor the config
--- names one. Spelled out rather than left to the CLI, because the download
--- check below has to know which file that is — and the CLI's default has
--- changed before (`small` until 2024, `turbo` since).
local DEFAULT_MODEL = "turbo"

--- Model names whose checkpoint file is not simply `<name>.pt`: the aliases
--- in `whisper/__init__.py`'s `_MODELS`, which point at the same URL.
---@type table<string, string>
local CHECKPOINT = {
  large = "large-v3.pt",
  turbo = "large-v3-turbo.pt",
}

--- Every name the CLI accepts (`whisper/__init__.py`'s `_MODELS`, 20250625),
--- so a typo reads as "unknown model" instead of "not downloaded yet".
---@type string[]
local KNOWN = {
  "tiny.en",
  "tiny",
  "base.en",
  "base",
  "small.en",
  "small",
  "medium.en",
  "medium",
  "large-v1",
  "large-v2",
  "large-v3",
  "large",
  "large-v3-turbo",
  "turbo",
}

--- Whether `model` is a checkpoint file rather than a name. The CLI accepts
--- both (`valid_model_name`: a known name, or a path that exists).
---@param model string
---@return boolean
local function is_path(model)
  return model:find("[/\\]") ~= nil or model:match("%.pt$") ~= nil
end

---@return string
local function cfg_model()
  local cfg = require("media.config").get().transcribe.openai_whisper or {}
  local model = cfg.model
  if type(model) == "string" and model ~= "" then return model end
  return DEFAULT_MODEL
end

--- Where whisper keeps downloaded models: `--model_dir` when configured,
--- otherwise the CLI's own default, `$XDG_CACHE_HOME/whisper` or
--- `~/.cache/whisper` (on Windows too — it is `os.path.expanduser("~")`).
---@return string
function M.model_dir()
  local cfg = require("media.config").get().transcribe.openai_whisper or {}
  if type(cfg.model_dir) == "string" and cfg.model_dir ~= "" then return cfg.model_dir end
  local xdg = os.getenv("XDG_CACHE_HOME")
  if xdg and xdg ~= "" then return xdg .. "/whisper" end
  return (uv.os_homedir() or "") .. "/.cache/whisper"
end

--- The checkpoint file a model name downloads to, inside `M.model_dir()`.
---
--- Pure and public so the name-to-file mapping is assertable without Python.
---@param model string
---@return string
function M.checkpoint(model)
  if is_path(model) then return model end
  return M.model_dir() .. "/" .. (CHECKPOINT[model] or (model .. ".pt"))
end

--- Whether `whisper` can be found at all.
---@return boolean
function M.available()
  return require("media.core.bin").find("whisper") ~= nil
end

--- The model a run would use, or why it cannot run: a checkpoint path that
--- does not exist, or a name not downloaded yet while downloads are not
--- allowed.
---@param model string|nil  # the call's own, before the config default
---@return string|nil model
---@return string|nil err
function M.resolve_model(model)
  if type(model) ~= "string" or model == "" then model = cfg_model() end

  local file = M.checkpoint(model)
  if uv.fs_stat(file) then return model, nil end
  if is_path(model) then return nil, "openai-whisper model not found: " .. model end
  if not vim.list_contains(KNOWN, model) then
    return nil,
      ("unknown openai-whisper model %q — one of %s, or a .pt path"):format(
        model,
        table.concat(KNOWN, ", ")
      )
  end

  local cfg = require("media.config").get().transcribe.openai_whisper or {}
  if cfg.allow_download then return model, nil end
  return nil,
    (
      "openai-whisper model %q is not downloaded yet (%s) — whisper would fetch it on first use; "
      .. "set `transcribe.openai_whisper.allow_download = true`, or run `whisper --model %s` once yourself"
    ):format(model, file, model)
end

--- Whether a run with `opts` could start right now: the binary is there and
--- the model is usable. What `engine = "auto"` asks before choosing this one.
---@param opts { model: string|nil }|nil
---@return boolean ready
---@return string|nil reason
function M.ready(opts)
  if not M.available() then return false, "`whisper` not found" end
  local model, err = M.resolve_model(opts and opts.model)
  if not model then return false, err end
  return true, nil
end

--- The argv for one run.
---
--- Pure and public for the reason `whisper_cpp.args` is.
---@param spec { bin: string, wav_path: string, model: string, out_dir: string, lang: string|nil, translate: boolean|nil, model_dir: string|nil, device: string|nil }
---@return string[]
function M.args(spec)
  local argv = {
    spec.bin,
    spec.wav_path,
    "--model",
    spec.model,
    "--output_format",
    "json",
    "--output_dir",
    spec.out_dir,
    -- No per-segment text on stdout; the progress bar still goes to stderr,
    -- which this engine reads only for a failure reason.
    "--verbose",
    "False",
  }
  if spec.lang then
    argv[#argv + 1] = "--language"
    argv[#argv + 1] = spec.lang
  end
  if spec.translate then
    argv[#argv + 1] = "--task"
    argv[#argv + 1] = "translate"
  end
  if spec.model_dir then
    argv[#argv + 1] = "--model_dir"
    argv[#argv + 1] = spec.model_dir
  end
  if spec.device then
    argv[#argv + 1] = "--device"
    argv[#argv + 1] = spec.device
  end
  return argv
end

--- The one sentence that says why a run failed, or nil.
---
--- In order: the CLI's own `Skipping <file> due to <Error>: <msg>` line (a
--- per-file failure, exit code 0, on stdout); argparse's `whisper: error:
--- <msg>` (a bad flag or model name, exit code 2, on stderr); the last
--- `<Name>Error: <msg>` line of a Python traceback (anything uncaught).
--- Pure and public, like `whisper_cpp.failure_reason`.
---@param stdout string|nil
---@param stderr string|nil
---@return string|nil
function M.failure_reason(stdout, stderr)
  if type(stdout) == "string" then
    local reason = nil
    for line in stdout:gmatch("[^\r\n]+") do
      local message = line:match("^Skipping .- due to (.+)$")
      if message then reason = vim.trim(message) end
    end
    if reason and reason ~= "" then return reason end
  end
  if type(stderr) ~= "string" then return nil end
  local argparse, traceback = nil, nil
  for line in stderr:gmatch("[^\r\n]+") do
    local message = line:match("^%S+: error:%s*(.+)$")
    if message then argparse = vim.trim(message) end
    if line:match("^[%w_%.]*Error: ") or line:match("^[%w_%.]*Exception: ") then
      traceback = vim.trim(line)
    end
  end
  return argparse or traceback
end

--- whisper's JSON shape: `segments` of `{ start, end, text }` in seconds,
--- plus the detected or forced `language`.
---@param doc table decoded JSON
---@param model string|nil
---@return Media.Transcript
function M.from_json(doc, model)
  return require("media.engines.whisper_cli").to_transcript(doc, M.id, model)
end

--- Transcribe `wav_path`.
---@param wav_path string
---@param opts Media.Engine.TranscribeOpts
---@param callback fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Engine.Job
function M.transcribe(wav_path, opts, callback)
  opts = opts or {}
  local cli = require("media.engines.whisper_cli")
  local own = require("media.config").get().transcribe.openai_whisper or {}

  local bin = require("media.core.bin").find("whisper")
  if not bin then
    return cli.fail(
      "whisper not found — `pip install openai-whisper`, or set `bin.whisper`",
      callback
    )
  end

  local model, merr = M.resolve_model(opts.model)
  if not model then return cli.fail(merr or "openai-whisper: no usable model", callback) end

  return cli.run({
    wav_path = wav_path,
    label = "whisper",
    env = cli.child_env(true),
    failure_reason = M.failure_reason,
    parse = function(doc)
      return M.from_json(doc, model)
    end,
    argv = function(out_dir)
      return M.args({
        bin = bin,
        wav_path = wav_path,
        model = model,
        out_dir = out_dir,
        lang = opts.lang,
        translate = opts.task == "translate",
        model_dir = (type(own.model_dir) == "string" and own.model_dir ~= "") and own.model_dir
          or nil,
        device = (type(own.device) == "string" and own.device ~= "") and own.device or nil,
      })
    end,
  }, callback)
end

return M
