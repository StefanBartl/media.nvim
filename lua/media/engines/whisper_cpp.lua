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
--- **Live-verified 2026-09-17**, against a real build and `ggml-base.en.bin`
--- on `samples/jfk.wav`. The JSON shape `M.from_json` reads was transcribed
--- from whisper.cpp's own source rather than observed, and the run confirmed
--- it exactly: `transcription[].offsets.{from,to}` in milliseconds,
--- `transcription[].text`, `result.language`. The hand-written fixture in
--- `TESTS/whisper_cpp_spec.lua` needed no change.
---
--- **What the same run disproved** is the claim that `-np` suppresses
--- everything: it does not, and more importantly `whisper-cli` **exits 0 on
--- some failures** — a file it cannot decode returns code 0, writes no JSON,
--- and reports the reason only on stderr. The exit code alone was therefore
--- never a sufficient test; see `M.failure_reason` and the no-JSON branch.

-- Resolved at load, on the main loop: it is called from `vim.system`'s
-- `on_exit`, a fast event context, where a first `require` can fail.
local exit_message = require("media.core.proc").exit_message

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

--- Neutral model names whose GGML file is not `ggml-<name>.bin` — the same
--- aliases openai-whisper resolves (`large` is v3, `turbo` is v3-turbo), so
--- `model=turbo` means one model whichever engine runs it.
---@type table<string, string>
local GGML_ALIASES = {
  large = "large-v3",
  turbo = "large-v3-turbo",
}

--- The GGML file a run would use, or why there is none.
---
--- `model` is what the caller asked for (`model=` / `transcribe.model`):
--- nil uses `transcribe.whisper_cpp.model`; a path (a separator, or `.bin`)
--- is taken as given; a bare name like `medium` or `large-v3` is looked up as
--- `ggml-<name>.bin` in `transcribe.whisper_cpp.model_dir`, then beside the
--- configured default model — the directory a person who downloaded one GGML
--- file has most likely put the others in. Never downloads anything.
---@param model string|nil
---@return string|nil path
---@return string|nil err
function M.resolve_model(model)
  local cfg = require("media.config").get().transcribe.whisper_cpp or {}
  local default = (type(cfg.model) == "string" and cfg.model ~= "") and cfg.model or nil

  if type(model) ~= "string" or model == "" then
    if not default then
      return nil,
        "no whisper.cpp model configured — set `transcribe.whisper_cpp.model` to a .bin file"
    end
    if not uv.fs_stat(default) then return nil, "whisper.cpp model not found: " .. default end
    return default, nil
  end

  if model:find("[/\\]") then
    if not uv.fs_stat(model) then return nil, "whisper.cpp model not found: " .. model end
    return model, nil
  end

  -- A bare file name (`ggml-medium.bin`) is looked for like a model name;
  -- a size name maps to its GGML file, through the aliases whose file is not
  -- `ggml-<name>.bin`.
  local file = model:match("%.bin$") and model
    or ("ggml-" .. (GGML_ALIASES[model] or model) .. ".bin")

  local dirs = {}
  if type(cfg.model_dir) == "string" and cfg.model_dir ~= "" then
    dirs[#dirs + 1] = cfg.model_dir
  end
  if default then dirs[#dirs + 1] = vim.fs.dirname(default) end
  for _, dir in ipairs(dirs) do
    local candidate = dir .. "/" .. file
    if uv.fs_stat(candidate) then return candidate, nil end
  end
  if file == model and uv.fs_stat(model) then return model, nil end
  return nil,
    (
      "no whisper.cpp model named %q — put %s into `transcribe.whisper_cpp.model_dir` "
      .. "(or beside `transcribe.whisper_cpp.model`), or pass a path"
    ):format(model, file)
end

--- Whether a run with `opts` could start right now: the binary and a model.
---
--- Separate from `available()` on purpose (see its note): an explicitly
--- chosen engine reports its own, specific error; `engine = "auto"` uses this
--- to pass over a whisper.cpp that is installed but has no model yet, and to
--- say why.
---@param opts { model: string|nil }|nil
---@return boolean ready
---@return string|nil reason
function M.ready(opts)
  if not M.available() then return false, "`whisper-cli` not found" end
  local path, err = M.resolve_model(opts and opts.model)
  if not path then return false, err end
  return true, nil
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
    -- Suppresses the system-info banner and the progress percentage. It does
    -- **not** suppress everything, which the module header used to claim:
    -- measured 2026-09-17 against a real build, a successful run still puts
    -- the transcribed segment on stdout (`[00:00:00.000 --> …] And so my
    -- fellow Americans…`) and three `read_audio_data:` lines on stderr. That
    -- is harmless here — this plugin reads the JSON file, not the streams —
    -- but it is why `M.failure_reason` picks the `error:` line out rather
    -- than handing a reader everything stderr happened to contain.
    "-np",
  }
  -- Always a language: **whisper-cli's own default is `en`, not detection**,
  -- so leaving `-l` out forced English on every run that asked for "let the
  -- engine detect it" — what `lang = nil` has always been documented as.
  -- `auto` is whisper.cpp's spelling of detection. Found in review,
  -- 2026-10-26.
  argv[#argv + 1] = "-l"
  argv[#argv + 1] = spec.lang or "auto"
  if spec.translate then
    -- whisper.cpp's own translate flag: source language in, English out.
    -- Every other target language is `language.nvim`'s job (ROADMAP.md).
    argv[#argv + 1] = "-tr"
  end
  return argv
end

--- The `error:` line out of whisper-cli's stderr, or nil when there is none.
---
--- Pure and public so the parsing is assertable without the binary. What it
--- picks out matters: `-np` leaves several `read_audio_data:` progress lines
--- on stderr (measured 2026-09-17 — see `M.args` on what `-np` does and does
--- not suppress), and handing all of them to a reader buries the one sentence
--- that says what went wrong. The last `error:` line is that sentence;
--- whisper.cpp prints the general one first and the specific one last.
---@param stderr string|nil
---@return string|nil
function M.failure_reason(stderr)
  if type(stderr) ~= "string" then return nil end
  local reason = nil
  for line in stderr:gmatch("[^\r\n]+") do
    local message = line:match("^%s*error:%s*(.+)$")
    if message then reason = vim.trim(message) end
  end
  if reason == "" then return nil end
  return reason
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

  local model, merr = M.resolve_model(opts.model)
  if not model then
    vim.schedule(function()
      finish(nil, merr)
    end)
    return job
  end

  -- A fresh, unique path per call — **not** derived from `wav_path`. Two
  -- concurrent transcriptions of the same file (nothing above this engine
  -- de-duplicates them) would otherwise compute the identical prefix, and
  -- the second call's own cleanup below would delete the first call's
  -- just-written result out from under it before it could be read — found
  -- in review, 2026-09-14. `vim.fn.tempname()` is already this ecosystem's
  -- way of getting a private scratch path (`pdfport.backends.tesseract`
  -- uses it the same way for its own rasterised pages).
  local out_prefix = vim.fn.tempname()
  local json_path = out_prefix .. ".json"

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
      finish(nil, stderr ~= "" and stderr or exit_message("whisper-cli", result.code))
      return
    end

    local fd = io.open(json_path, "r")
    if not fd then
      -- **`whisper-cli` exits 0 on some failures**, so the check above cannot
      -- be the only one. Measured 2026-09-17 against a real build: a file it
      -- cannot decode gives code **0**, writes no JSON, and puts
      -- `error: failed to read audio file '…'` on stderr. Before this, the
      -- reader got "reported success but wrote no JSON" and the actual
      -- reason — sitting right there in stderr — was discarded.
      finish(nil, M.failure_reason(result.stderr) or ("whisper-cli wrote no JSON: " .. json_path))
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
