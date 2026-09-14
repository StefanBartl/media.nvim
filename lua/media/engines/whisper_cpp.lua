---@module 'media.engines.whisper_cpp'
---@brief Local transcription via whisper.cpp's `whisper-cli`.
---@description
--- The default engine (ROADMAP.md's open decision on the point): no Python
--- toolchain, the best-supported story on Windows, GGML models. Shells out to
--- `whisper-cli -m <model> -f <wav> -oj -of <prefix>`, which writes
--- `<prefix>.json` — read back from disk, not parsed off stdout, because
--- whisper.cpp's JSON carries the timestamped segments in a stable shape
--- stdout has never promised to keep.
---
--- **Not live-verified.** No whisper.cpp binary or GGML model is installed on
--- the machine this was written on; the JSON shape `M.from_json` reads is
--- transcribed from whisper.cpp's own `examples/main/main.cpp`
--- (`output_json`), not observed against a real run. `:checkhealth media`
--- says plainly when the binary or the model is missing rather than
--- pretending either is there — see the module note on `media.transcribe`
--- for what to check before trusting this against a real file.

local uv = vim.uv or vim.loop

--- Declared as a class, like `PdfPort.Backend.Tesseract`, so the methods
--- below the literal count as implementing `Media.Engine`.
---@class Media.Engine.WhisperCpp : Media.Engine
local M = {
  id = "whisper_cpp",
  name = "whisper.cpp (local, GGML)",
  capabilities = {
    local_ = true,
    remote = false,
    segments = true,
    translate_to_en = true,
  },
}

--- Whether `whisper-cli` can be found at all. Deliberately not "and a model
--- is configured" — that is `transcribe`'s own, more specific error, kept
--- separate so a missing model reads as "set `transcribe.whisper_cpp.model`"
--- rather than as "engine unavailable", which would send the resolver
--- looking for a fallback that does not yet exist in phase 0.
---@return boolean
function M.available()
  return require("media.core.bin").find("whisper-cli") ~= nil
end

--- The argv for one run.
---
--- Pure and public for the same reason `frame.args` is: the flag order is
--- the entire content of this module's process-spawning half, and it should
--- be assertable without the binary installed.
---@param spec { bin: string, wav_path: string, model: string, out_prefix: string, lang: string|nil, translate: boolean|nil }
---@return string[]
function M.args(spec)
  local argv = {
    spec.bin,
    "-m",
    spec.model,
    "-f",
    spec.wav_path,
    -- JSON output, not stdout: see the module note on why.
    "-oj",
    "-of",
    spec.out_prefix,
    -- No system-info banner or per-segment prints on stdout — this plugin
    -- reads the JSON file, and whisper.cpp's own progress spam would
    -- otherwise be the only thing in `result.stdout`/`stderr` to look at
    -- when something goes wrong.
    "-np",
  }
  if spec.lang then
    argv[#argv + 1] = "-l"
    argv[#argv + 1] = spec.lang
  end
  if spec.translate then
    -- whisper.cpp's own translate flag: source language in, English out.
    -- Every other target language is `language.nvim`'s job (ROADMAP.md).
    argv[#argv + 1] = "-tr"
  end
  return argv
end

--- whisper.cpp's own `-oj` shape: a `transcription` array of
--- `{ offsets = { from, to }, text }`, offsets in milliseconds, plus
--- `result.language` when the engine detected it.
---@param doc table decoded JSON
---@param model string|nil
---@return Media.Transcript
function M.from_json(doc, model)
  local segments = {}
  local entries = type(doc.transcription) == "table" and doc.transcription or {}
  for i, entry in ipairs(entries) do
    local offsets = type(entry.offsets) == "table" and entry.offsets or {}
    segments[i] = {
      s = (tonumber(offsets.from) or 0) / 1000,
      e = (tonumber(offsets.to) or 0) / 1000,
      text = type(entry.text) == "string" and vim.trim(entry.text) or "",
    }
  end

  local result = type(doc.result) == "table" and doc.result or {}

  return {
    engine = M.id,
    model = model,
    lang = type(result.language) == "string" and result.language or nil,
    duration = nil,
    segments = segments,
    text = require("media.core.segments").to_text(segments),
  }
end

--- Transcribe `wav_path`.
---@param wav_path string
---@param opts Media.Engine.TranscribeOpts
---@param callback fun(transcript: Media.Transcript|nil, err: string|nil): nil
---@return Media.Engine.Job
function M.transcribe(wav_path, opts, callback)
  opts = opts or {}
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

  local bin = require("media.core.bin").find("whisper-cli")
  if not bin then
    vim.schedule(function()
      finish(nil, 'whisper-cli not found — install whisper.cpp, or set `bin["whisper-cli"]`')
    end)
    return job
  end

  local model = opts.model or cfg.whisper_cpp.model
  if type(model) ~= "string" or model == "" then
    vim.schedule(function()
      finish(
        nil,
        "no whisper.cpp model configured — set `transcribe.whisper_cpp.model` to a .bin file"
      )
    end)
    return job
  end
  if not uv.fs_stat(model) then
    vim.schedule(function()
      finish(nil, "whisper.cpp model not found: " .. model)
    end)
    return job
  end

  -- whisper.cpp appends the extension itself (`-of` is a prefix, `.json` is
  -- added), and the WAV already ends in `.wav` — stripped so the prefix does
  -- not read as `…wav.json`.
  local out_prefix = (wav_path:gsub("%.wav$", ""))
  local json_path = out_prefix .. ".json"
  -- A leftover from a run that died mid-write would otherwise read as this
  -- run's result; whisper.cpp has no `-y` of its own to make that explicit.
  os.remove(json_path)

  local argv = M.args({
    bin = bin,
    wav_path = wav_path,
    model = model,
    out_prefix = out_prefix,
    lang = opts.lang,
    translate = opts.task == "translate",
  })

  -- `0` means "no timeout" (the phase-0 default — see `transcribe.timeout_ms`
  -- in DEFAULTS.lua for why); `vim.system` takes that as "wait a fraction of
  -- a second", not "forever", so it is passed as `nil` instead.
  local timeout = (cfg.timeout_ms and cfg.timeout_ms > 0) and cfg.timeout_ms or nil

  proc = vim.system(argv, { text = true, timeout = timeout }, function(result)
    proc = nil
    if result.code ~= 0 then
      local stderr = (result.stderr or ""):gsub("%s+$", "")
      finish(nil, stderr ~= "" and stderr or ("whisper-cli exited with " .. tostring(result.code)))
      return
    end

    local fd = io.open(json_path, "r")
    if not fd then
      finish(nil, "whisper-cli reported success but wrote no JSON: " .. json_path)
      return
    end
    local content = fd:read("*a")
    fd:close()
    os.remove(json_path)

    local ok, doc = pcall(vim.json.decode, content)
    if not ok or type(doc) ~= "table" then
      finish(nil, "whisper-cli's JSON output could not be read")
      return
    end

    finish(M.from_json(doc, model), nil)
  end)

  return job
end

return M
