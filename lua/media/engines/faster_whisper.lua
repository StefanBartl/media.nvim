---@module 'media.engines.faster_whisper'
---@brief Local transcription via faster-whisper's CLI, `whisper-ctranslate2`.
---@description
--- The third engine (ROADMAP.md: "faster_whisper, local, CTranslate2, fastest
--- per watt"). `pip install whisper-ctranslate2` installs a console entry
--- point with openai-whisper's command line, run on CTranslate2 instead of
--- PyTorch: several times faster on a CPU at the same accuracy, and no
--- ffmpeg needed (it decodes through PyAV).
---
--- **Read from the source, whisper-ctranslate2 0.5.8 / faster-whisper
--- master** (`commandline.py`, `whisper_ctranslate2.py`, `transcribe.py`,
--- `writers.py`; `faster_whisper/utils.py`): the same JSON as openai-whisper
--- (`{ text, segments = [{ start, end, text, … }], language }`, seconds),
--- written to `<output_dir>/<audio basename>.json`. A failure while
--- transcribing one file is caught and written to **stderr** as `Error:
--- Unable to process file` / `Exception Type:` / `Exception Message:`, exit
--- code 0; a model that cannot be loaded is `error: <msg>` on **stdout**,
--- exit code non-zero. See `M.failure_reason`.
---
--- **Models** are Hugging Face repositories (`Systran/faster-whisper-<name>`,
--- `mobiuslabsgmbh/faster-whisper-large-v3-turbo`, …), fetched into the HF
--- cache on first use. Same rule as `openai_whisper`: a model not in the
--- cache is an error unless `transcribe.faster_whisper.allow_download` is set
--- — and here it is enforced twice, because the CLI has a switch for it:
--- `--local_files_only True` makes the tool itself refuse the download.
---
--- **`large` is not a name this CLI accepts** (its `--model` choices stop at
--- `large-v1`…`large-v3`); the neutral `large` maps to `large-v3`, as it does
--- for the other two engines.

local uv = vim.uv or vim.loop

---@class Media.Engine.FasterWhisper : Media.Engine
local M = {
  id = "faster_whisper",
  name = "faster-whisper (local, CTranslate2)",
  capabilities = {
    local_ = true,
    remote = false,
    segments = true,
    translate_to_en = true,
  },
}

--- The CLI's own `--model` default, spelled out for the download check.
local DEFAULT_MODEL = "small"

--- Every `--model` choice of whisper-ctranslate2 0.5.8, and the Hugging Face
--- repository faster-whisper downloads it from (`faster_whisper/utils.py`).
---@type table<string, string>
local REPOS = {
  ["tiny"] = "Systran/faster-whisper-tiny",
  ["tiny.en"] = "Systran/faster-whisper-tiny.en",
  ["base"] = "Systran/faster-whisper-base",
  ["base.en"] = "Systran/faster-whisper-base.en",
  ["small"] = "Systran/faster-whisper-small",
  ["small.en"] = "Systran/faster-whisper-small.en",
  ["medium"] = "Systran/faster-whisper-medium",
  ["medium.en"] = "Systran/faster-whisper-medium.en",
  ["large-v1"] = "Systran/faster-whisper-large-v1",
  ["large-v2"] = "Systran/faster-whisper-large-v2",
  ["large-v3"] = "Systran/faster-whisper-large-v3",
  ["large-v3-turbo"] = "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
  ["turbo"] = "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
  ["distil-large-v2"] = "Systran/faster-distil-whisper-large-v2",
  ["distil-large-v3"] = "Systran/faster-distil-whisper-large-v3",
  ["distil-large-v3.5"] = "distil-whisper/distil-large-v3.5-ct2",
  ["distil-medium.en"] = "Systran/faster-distil-whisper-medium.en",
  ["distil-small.en"] = "Systran/faster-distil-whisper-small.en",
}

--- Neutral names this CLI spells differently.
---@type table<string, string>
local ALIASES = { large = "large-v3" }

---@return table
local function own_cfg()
  return require("media.config").get().transcribe.faster_whisper or {}
end

---@param s any
---@return string|nil
local function nonempty(s)
  if type(s) == "string" and s ~= "" then return s end
  return nil
end

--- Whether `model` is a local model directory rather than a name. Such a
--- directory (a converted CTranslate2 model, `model.bin` inside) goes to
--- `--model_directory`, never through the download check.
---@param model string
---@return boolean
local function is_path(model)
  return model:find("[/\\]") ~= nil
end

--- `~` at the start of a path, expanded the way Python's `expanduser`
--- does — huggingface_hub expands every one of the variables below.
---@param path string
---@return string
local function expand_home(path)
  if path == "~" or path:match("^~[/\\]") then return (uv.os_homedir() or "") .. path:sub(2) end
  return path
end

--- The Hugging Face hub cache faster-whisper downloads into:
--- `transcribe.faster_whisper.model_dir` (the CLI's `--model_dir`, passed
--- straight to `snapshot_download(cache_dir=…)`), else huggingface_hub's own
--- order (`huggingface_hub/constants.py`): `$HF_HUB_CACHE`, the older
--- `$HUGGINGFACE_HUB_CACHE`, then `<HF home>/hub`, where the HF home is
--- `$HF_HOME`, else `$XDG_CACHE_HOME/huggingface`, else
--- `~/.cache/huggingface`. Found in review, 2026-10-26: without the XDG step
--- a Linux machine with `XDG_CACHE_HOME` set reported every downloaded model
--- as missing.
---@return string
function M.cache_dir()
  local configured = nonempty(own_cfg().model_dir)
  if configured then return expand_home(configured) end
  local hub = nonempty(os.getenv("HF_HUB_CACHE")) or nonempty(os.getenv("HUGGINGFACE_HUB_CACHE"))
  if hub then return expand_home(hub) end
  local home = nonempty(os.getenv("HF_HOME"))
  if not home then
    local xdg = nonempty(os.getenv("XDG_CACHE_HOME"))
    home = xdg and (xdg .. "/huggingface") or "~/.cache/huggingface"
  end
  return expand_home(home) .. "/hub"
end

--- Whether a cache entry holds a complete model: some snapshot with a
--- `model.bin` in it. A download that was cut off leaves `blobs/*.incomplete`
--- and a `refs/` directory but no usable snapshot — the bare directory test
--- this replaced counted that as downloaded, `auto` chose the engine, and the
--- run then failed on `--local_files_only` with nothing to fall back to.
--- Found in review, 2026-10-26.
---@param entry string
---@return boolean
local function complete(entry)
  local handle = uv.fs_scandir(entry .. "/snapshots")
  if not handle then return false end
  while true do
    local name = uv.fs_scandir_next(handle)
    if not name then return false end
    if uv.fs_stat(entry .. "/snapshots/" .. name .. "/model.bin") then return true end
  end
end

--- The model names whose cache entry is complete, sorted — what
--- `:checkhealth media` lists. Only this CLI's own repositories count: a
--- shared Hugging Face cache also holds `models--openai--whisper-*`
--- (Transformers checkpoints) that faster-whisper cannot load.
---@return string[]
function M.cached_models()
  local out = {}
  for name in pairs(REPOS) do
    local entry = M.cache_entry(name)
    if entry and complete(entry) then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

--- The cache directory a model name downloads to, or nil for an unknown
--- name. huggingface_hub names it `models--<org>--<repo>`.
---
--- Pure and public so the mapping is assertable without Python.
---@param model string
---@return string|nil
function M.cache_entry(model)
  local repo = REPOS[ALIASES[model] or model]
  if not repo then return nil end
  return M.cache_dir() .. "/models--" .. repo:gsub("/", "--")
end

--- Whether `whisper-ctranslate2` can be found at all.
---@return boolean
function M.available()
  return require("media.core.bin").find("whisper-ctranslate2") ~= nil
end

--- The `--model` value a run would use, or why it cannot run.
---@param model string|nil  # the call's own, before the config default
---@return string|nil model  # a CLI model name, or a model directory
---@return string|nil err
function M.resolve_model(model)
  model = nonempty(model) or nonempty(own_cfg().model) or DEFAULT_MODEL

  if is_path(model) then
    if not uv.fs_stat(model .. "/model.bin") then
      return nil, "faster-whisper model directory has no model.bin: " .. model
    end
    return model, nil
  end

  local name = ALIASES[model] or model
  local entry = M.cache_entry(name)
  if not entry then
    local names = vim.tbl_keys(REPOS)
    table.sort(names)
    return nil,
      ("unknown faster-whisper model %q — one of %s, or a model directory"):format(
        model,
        table.concat(names, ", ")
      )
  end
  if complete(entry) or own_cfg().allow_download then return name, nil end
  return nil,
    (
      "faster-whisper model %q is not downloaded yet (%s) — set "
      .. "`transcribe.faster_whisper.allow_download = true`, or run `whisper-ctranslate2 --model %s` once yourself"
    ):format(name, entry, name)
end

--- The CLI's `--device` choices. openai-whisper takes any torch device
--- (`cuda:0`, `mps`); this one rejects those in argparse, after the WAV has
--- been extracted.
---@type string[]
local DEVICES = { "auto", "cpu", "cuda" }

--- Why the configured `device` would be rejected, or nil.
---@return string|nil
function M.device_error()
  local device = nonempty(own_cfg().device)
  if device and not vim.list_contains(DEVICES, device) then
    return ("transcribe.faster_whisper.device must be one of %s, got %q"):format(
      table.concat(DEVICES, ", "),
      device
    )
  end
  return nil
end

--- Whether a run with `opts` could start right now.
---@param opts { model: string|nil }|nil
---@return boolean ready
---@return string|nil reason
function M.ready(opts)
  if not M.available() then return false, "`whisper-ctranslate2` not found" end
  local derr = M.device_error()
  if derr then return false, derr end
  local model, err = M.resolve_model(opts and opts.model)
  if not model then return false, err end
  return true, nil
end

--- The argv for one run.
---
--- Pure and public for the reason `whisper_cpp.args` is.
---@param spec { bin: string, wav_path: string, model: string, out_dir: string, lang: string|nil, translate: boolean|nil, model_dir: string|nil, device: string|nil, offline: boolean|nil }
---@return string[]
function M.args(spec)
  local argv = { spec.bin, spec.wav_path }
  if is_path(spec.model) then
    argv[#argv + 1] = "--model_directory"
  else
    argv[#argv + 1] = "--model"
  end
  argv[#argv + 1] = spec.model
  vim.list_extend(argv, {
    "--output_format",
    "json",
    "--output_dir",
    spec.out_dir,
    "--verbose",
    "False",
  })
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
  if spec.offline then
    -- The tool's own refusal to download, behind `resolve_model`'s check:
    -- a cache entry that exists but is incomplete would otherwise be
    -- "repaired" by a silent multi-gigabyte fetch.
    argv[#argv + 1] = "--local_files_only"
    argv[#argv + 1] = "True"
  end
  return argv
end

--- The one sentence that says why a run failed, or nil.
---
--- In order: the per-file `Exception Type:` / `Exception Message:` pair on
--- stderr (exit code 0); `error: <msg>` on stdout (the model could not be
--- loaded); argparse's `whisper-ctranslate2: error: <msg>` on stderr; a
--- `Model file '…' does not exist` line; the last `<Name>Error:` line of an
--- uncaught traceback.
---@param stdout string|nil
---@param stderr string|nil
---@return string|nil
function M.failure_reason(stdout, stderr)
  if type(stderr) == "string" then
    local kind = stderr:match("Exception Type:%s*([^\r\n]+)")
    local message = stderr:match("Exception Message:%s*([^\r\n]*)")
    if kind then
      kind = vim.trim(kind)
      message = message and vim.trim(message) or ""
      return message ~= "" and (kind .. ": " .. message) or kind
    end
  end
  if type(stdout) == "string" then
    local loaded = nil
    for line in stdout:gmatch("[^\r\n]+") do
      local message = line:match("^error:%s*(.+)$")
      if message then loaded = vim.trim(message) end
    end
    if loaded and loaded ~= "" then return loaded end
  end
  if type(stderr) ~= "string" then return nil end
  local argparse, missing, traceback = nil, nil, nil
  for line in stderr:gmatch("[^\r\n]+") do
    local message = line:match("^%S+: error:%s*(.+)$")
    if message then argparse = vim.trim(message) end
    if line:match("^Model file '.-' does not exist") then missing = vim.trim(line) end
    if line:match("^[%w_%.]*Error: ") or line:match("^[%w_%.]*Exception: ") then
      traceback = vim.trim(line)
    end
  end
  -- `--local_files_only True` refusing a model that is not (completely) in
  -- the cache: huggingface_hub's own message says "pass
  -- local_files_only=False", which is not a setting anyone here has.
  if traceback and traceback:find("LocalEntryNotFoundError", 1, true) then
    return "the faster-whisper model is not (completely) in the Hugging Face cache and downloads "
      .. "are off — set `transcribe.faster_whisper.allow_download = true` ("
      .. traceback
      .. ")"
  end
  return argparse or missing or traceback
end

--- whisper-ctranslate2's JSON — openai-whisper's shape.
---@param doc table
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
  local own = own_cfg()

  local bin = require("media.core.bin").find("whisper-ctranslate2")
  if not bin then
    return cli.fail(
      'whisper-ctranslate2 not found — `pip install whisper-ctranslate2`, or set `bin["whisper-ctranslate2"]`',
      callback
    )
  end

  local derr = M.device_error()
  if derr then return cli.fail(derr, callback) end

  local model, merr = M.resolve_model(opts.model)
  if not model then return cli.fail(merr or "faster-whisper: no usable model", callback) end

  return cli.run({
    wav_path = wav_path,
    label = "whisper-ctranslate2",
    env = cli.child_env(false),
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
        model_dir = nonempty(own.model_dir),
        device = nonempty(own.device),
        offline = not own.allow_download,
      })
    end,
  }, callback)
end

return M
