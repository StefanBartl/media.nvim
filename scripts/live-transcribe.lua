-- scripts/live-transcribe.lua -- run one real transcription through the real pipeline.
--
-- The specs cover every engine against a fake `vim.system`; this is the other
-- half, for the "once live against the real tool" step an engine change needs
-- (docs/CONTRIBUTING.md). It runs `media.transcribe` headless and prints what
-- an engine produced, how long it took, and what `auto` would choose.
--
--   nvim --headless -u NONE -l scripts/live-transcribe.lua <file> [key=value ...]
--
-- Keys (all optional): engine= lang= model= task= (as for :Media transcribe),
-- allow_download=true (faster/openai), ffmpeg=<path> ffprobe=<path>
-- whisper-cli=<path> whisper=<path> whisper-ctranslate2=<path> (bin overrides),
-- whisper_cpp_model_dir=<dir>. The cache is always off, so every run is real.
--
-- Exit code 0 on a transcript, 1 on an error.

local here = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local repo = vim.fs.normalize(here .. "..")
-- Prepended, not appended: an installed copy of media.nvim or lib.nvim earlier
-- on the runtimepath would otherwise be the one that runs.
local lib = os.getenv("LIB_NVIM_DIR") or (repo .. "/../lib.nvim")
if vim.uv.fs_stat(lib) then vim.opt.rtp:prepend(lib) end
vim.opt.rtp:prepend(repo)

local file = arg[1]
if not file then
  io.stderr:write(
    "usage: nvim --headless -u NONE -l scripts/live-transcribe.lua <file> [key=value ...]\n"
  )
  os.exit(2)
end

--- Every key this script understands. A typo (`lang auto`, `engin=…`) must
--- stop the run, not silently fall back to a default and measure the wrong
--- thing.
---@type table<string, true>
local KEYS = {
  engine = true,
  lang = true,
  model = true,
  task = true,
  allow_download = true,
  ffmpeg = true,
  ffprobe = true,
  ["whisper-cli"] = true,
  whisper = true,
  ["whisper-ctranslate2"] = true,
  whisper_cpp_model_dir = true,
}

local kv = {}
for i = 2, #arg do
  local k, v = arg[i]:match("^([%w_%-]+)=(.*)$")
  if not k or not KEYS[k] then
    io.stderr:write(
      ("unknown argument %q — expected key=value with one of the keys in the header\n"):format(
        arg[i]
      )
    )
    os.exit(2)
  end
  -- `model=` (empty) means "not given", as it does for :Media transcribe.
  if v ~= "" then kv[k] = v end
end

local bin = {}
for _, name in ipairs({ "ffmpeg", "ffprobe", "whisper-cli", "whisper", "whisper-ctranslate2" }) do
  if kv[name] then bin[name] = kv[name] end
end
local allow = kv.allow_download == "true"
require("media.config").setup({
  bin = bin,
  transcribe = {
    whisper_cpp = { model_dir = kv.whisper_cpp_model_dir },
    faster_whisper = { allow_download = allow },
    openai_whisper = { allow_download = allow },
  },
})

---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local registry = require("media.core.registry")
require("media.engines").load_all()
for _, id in ipairs(registry.ids()) do
  local engine = registry.get(id)
  local ok, avail = pcall(engine.available)
  local state = (ok and avail) and "available" or "unavailable"
  if ok and avail and engine.ready then
    local rok, ready, why = pcall(engine.ready, { model = kv.model })
    if rok and not ready then state = "available, not ready: " .. tostring(why) end
  end
  say(("engine %-16s %s"):format(id, state))
end
local chosen, why = require("media.core.resolver").resolve(kv.engine, { model = kv.model })
say("resolves to: " .. (chosen and chosen.id or ("nothing — " .. tostring(why))))

local result, done = nil, false
local started = vim.uv.hrtime()
require("media").transcribe(file, {
  engine = kv.engine,
  lang = kv.lang,
  model = kv.model,
  task = kv.task,
  cache = false,
  on_phase = function(info)
    say(("phase: %s%s"):format(info.phase, info.engine and (" (" .. info.engine .. ")") or ""))
  end,
}, function(t, err)
  result, done = { t = t, err = err }, true
end)
vim.wait(24 * 3600 * 1000, function()
  return done
end, 200)
local secs = (vim.uv.hrtime() - started) / 1e9

if not done then
  -- `vim.wait` gave up (the day-long ceiling, or an interrupt): there is no
  -- result to report, and indexing it would end in a traceback.
  say(("error after %.1fs: no result — timed out or interrupted"):format(secs))
  os.exit(1)
end

if result.t then
  local t = result.t
  say(
    ("ok: engine=%s model=%s lang=%s segments=%d %.1fs"):format(
      t.engine,
      tostring(t.model),
      tostring(t.lang),
      #t.segments,
      secs
    )
  )
  say(t.text)
  os.exit(0)
end
say(("error after %.1fs: %s"):format(secs, tostring(result.err)))
os.exit(1)
