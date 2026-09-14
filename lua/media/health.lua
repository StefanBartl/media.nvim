---@module 'media.health'
---@brief `:checkhealth media`.
---@description
--- Answers the three questions that actually go wrong, in the order they go
--- wrong in: are the binaries there, is the cache writable, and which optional
--- neighbours are present. The second one exists because its failure is silent
--- otherwise — a read-only cache directory produces "no frame was written" from
--- a renderer that ran perfectly.

local M = {}

local health = vim.health or require("health")
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_err = health.error or health.report_error
local h_start = health.start or health.report_start
local h_info = health.info or health.report_info

---@internal
---@param name "ffmpeg"|"ffprobe"
---@return boolean
local function check_bin(name)
  local bin = require("media.core.bin")
  local found = bin.find(name)
  if not found then
    h_err(("%s not found"):format(name), {
      "Install ffmpeg — it ships both binaries.",
      "Windows: `winget install Gyan.FFmpeg`, then restart the terminal so PATH is picked up.",
      "macOS: `brew install ffmpeg`.  Debian/Ubuntu: `sudo apt install ffmpeg`.",
      ('Or point at it directly: `require("media").setup({ bin = { %s = "…" } })`'):format(name),
    })
    return false
  end
  h_ok(("%s found: %s"):format(name, found))
  return true
end

---@internal
---@return nil
local function check_version()
  local ffmpeg = require("media.core.bin").find("ffmpeg")
  if not ffmpeg then return end
  -- Synchronous on purpose: `:checkhealth` renders its report when the
  -- function returns, so an asynchronous answer arrives after the section it
  -- belongs to has already been written.
  local ok, result = pcall(function()
    return vim.system({ ffmpeg, "-hide_banner", "-version" }, { text = true }):wait(5000)
  end)
  if not ok or type(result) ~= "table" or result.code ~= 0 then
    h_warn("ffmpeg was found but would not report its version")
    return
  end
  local first = (result.stdout or ""):match("^[^\r\n]*") or ""
  h_info(first ~= "" and first or "ffmpeg version unknown")
end

---@internal
---@return nil
local function check_cache()
  local ok, dir = pcall(function()
    return require("media.core.cache").dir()
  end)
  if not ok then
    h_err("the cache directory could not be created: " .. tostring(dir))
    return
  end

  local probe_file = dir .. "/.writable"
  local fd = io.open(probe_file, "w")
  if not fd then
    h_err(("cache directory is not writable: %s"):format(dir), {
      "Set `cache.dir` to somewhere writable, or fix the permissions.",
    })
    return
  end
  fd:close()
  os.remove(probe_file)
  h_ok("cache directory is writable: " .. dir)
end

---@internal
---@param module string
---@param what string
---@return nil
local function check_optional(module, what)
  if pcall(require, module) then
    h_ok(("%s found — %s"):format(module, what))
  else
    h_info(("%s not installed — %s"):format(module, what))
  end
end

---@return nil
function M.check()
  h_start("media.nvim: toolchain")
  local ffmpeg = check_bin("ffmpeg")
  local ffprobe = check_bin("ffprobe")
  if ffmpeg and ffprobe then check_version() end

  h_start("media.nvim: cache")
  check_cache()

  h_start("media.nvim: optional integrations")
  check_optional("lib.nvim", "keymap registry, `:Media` completion, scratch windows")
  check_optional(
    "images",
    "rendered stills are shown in the terminal instead of an external viewer"
  )

  h_start("media.nvim: mpv")
  local mpv = require("media.core.audio").find_mpv()
  if mpv then
    h_ok("mpv found: " .. mpv)
    h_info(
      "`media.audio` can give a played run sound, and `:Media window` opens a real player window"
    )
  else
    h_info(
      "mpv not found — a played run stays silent and `:Media window` cannot open, never an error"
    )
    h_info(
      "install it: winget install mpv-player.mpv (Windows), "
        .. "brew install mpv (macOS), apt install mpv (Debian/Ubuntu) — "
        .. 'or set `require("media").setup({ bin = { mpv = "…" } })`'
    )
  end

  h_start("media.nvim: transcription")
  local whisper_bin = require("media.core.bin").find("whisper-cli")
  if whisper_bin then
    h_ok("whisper-cli found: " .. whisper_bin)
  else
    h_info(
      "whisper-cli not found — `media.transcribe`/`:Media transcribe` cannot run, never an error elsewhere"
    )
    h_info(
      "install whisper.cpp and build `whisper-cli`, then set "
        .. '`require("media").setup({ bin = { ["whisper-cli"] = "…" } })`'
        .. " if it lands off PATH"
    )
  end
  local model = require("media.config").get().transcribe.whisper_cpp.model
  if type(model) == "string" and model ~= "" then
    if (vim.uv or vim.loop).fs_stat(model) then
      h_ok("whisper.cpp model: " .. model)
    else
      h_warn("`transcribe.whisper_cpp.model` is set but the file does not exist: " .. model)
    end
  else
    h_info(
      "no whisper.cpp model configured — set `transcribe.whisper_cpp.model` to a GGML .bin "
        .. "file (never downloaded automatically)"
    )
  end

  h_start("media.nvim: what is claimed")
  local video, audio = require("media.formats").known()
  h_info(("video: %s"):format(table.concat(video, ", ")))
  h_info(("audio: %s"):format(table.concat(audio, ", ")))

  local player = require("media.config").get().player
  if player == nil then
    h_info("`player` is unset — `:Media play` uses the system's default handler")
  else
    local argv, err = require("media.core.play").player()
    if argv then
      h_ok("player: " .. table.concat(argv, " "))
    else
      h_warn(err or "the configured player could not be resolved")
    end
  end

  if vim.fn.has("win32") == 1 then
    h_info(
      "Windows: a player started from a terminal Neovim opens behind the terminal window — "
        .. "Windows only grants focus to the process owning the foreground window. "
        .. "`:Media window` passes `--ontop` so it stays visible anyway (`window.ontop = false` to opt out)."
    )
  end
end

return M
