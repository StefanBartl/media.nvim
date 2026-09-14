---@module 'media.bindings.usrcmds'
---@brief Registers `:Media <subcommand>`, one verb built via lib.nvim's composer.
---@description
--- Bare `:Media [path]` describes the file — the cheapest useful answer, and
--- the one that tells you whether the others are worth asking for. `frame` and
--- `sheet` render a picture; `play` hands the file to a real player; `cache
--- clear` throws the rendered stills away.
---
--- Every path-taking route accepts an optional path and falls back to `<cfile>`
--- and then to the current buffer's name, so the commands work from a file tree
--- and from a list of links without an argument. See `docs/BINDINGS.md` for the
--- cheatsheet.
---
--- **`M.run` is the shared body.** The keymaps invoke the same four actions, and
--- one of the recurring defects in this ecosystem is a command and its key
--- drifting apart because each grew its own copy of the work.

local M = {}

---@internal
--- Path completion that offers media files first.
---
--- Meaningfully different from the composer's built-in PATH type (a plain
--- `getcompletion`), which is why it is registered as its own type rather than
--- left to the built-in: in a directory of a hundred files, the four this
--- plugin can do anything with should not be in alphabetical order among them.
---@param arg_lead string
---@return string[]
local function complete_media_path(arg_lead)
  local formats = require("media.formats")

  if arg_lead == "" then
    local cfile = vim.fn.expand("<cfile>")
    if cfile and cfile ~= "" and vim.fn.filereadable(cfile) == 1 then return { cfile } end
    return {}
  end

  local media, rest = {}, {}
  for _, path in ipairs(vim.fn.glob(arg_lead .. "*", false, true)) do
    if formats.is_media(path) then
      media[#media + 1] = path
    else
      rest[#rest + 1] = path
    end
  end
  return vim.list_extend(media, rest)
end

--- The path a command acts on when it was given none.
---@param explicit string|nil
---@return string|nil
function M.resolve_path(explicit)
  if explicit and explicit ~= "" then return vim.fn.expand(explicit) end
  return require("media.bindings.keymaps").target()
end

---@internal
---@param message string
---@param level integer|nil
---@return nil
local function say(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "media.nvim" })
end

---@internal
---@param engine Media.Engine|nil
---@return boolean
local function engine_available(engine)
  if not engine then return false end
  local ok, avail = pcall(engine.available)
  return ok and avail == true
end

--- Perform one action on one path. The single body behind both the commands and
--- the keymaps.
---@param action "probe"|"frame"|"sheet"|"waveform"|"spectrogram"|"transcribe"|"play"|"window"
---@param path string
---@param opts table|nil  # forwarded to frame/sheet/window
---@return nil
function M.run(action, path, opts)
  local ui = require("media.ui")

  if action == "probe" then
    ui.show_probe(path)
    return
  end

  if action == "play" then
    local ok, err = require("media").play(path)
    if not ok then say(err or "could not play this file", vim.log.levels.ERROR) end
    return
  end

  if action == "window" then
    -- A real mpv window, unlike `play` which hands the file to whatever the
    -- user configured (or the system default). This one is always mpv and is
    -- stopped at `:qa` — see `media.core.player`. The handle is dropped
    -- deliberately: from `:Media` there is no UI element to tie it to, so it
    -- lives until mpv or the editor exits.
    local at = opts and opts.at or nil
    local _, err = require("media").play_window(path, {
      at = (type(at) == "number" or type(at) == "string") and at or nil,
    })
    if err then say(err, vim.log.levels.ERROR) end
    return
  end

  if action == "frame" or action == "sheet" or action == "waveform" or action == "spectrogram" then
    -- Said before the render rather than after it: a contact sheet of a long
    -- file takes seconds, and silence in that window reads as "the key did
    -- nothing" — which is exactly when a second press starts a second render.
    say(("rendering %s…"):format(action))
    local renderers = {
      frame = require("media").frame,
      sheet = require("media").sheet,
      waveform = require("media").waveform,
      spectrogram = require("media").spectrogram,
    }
    renderers[action](path, opts, function(png, err)
      if not png then
        say(err or (action .. " failed"), vim.log.levels.ERROR)
        return
      end
      ui.show_image(png)
    end)
    return
  end

  if action == "transcribe" then
    -- Transcription is minutes, not seconds (ROADMAP.md's "Risks and known
    -- traps") — said up front for the same reason `frame`/`sheet` say
    -- "rendering…" before starting, except here the silence it prevents
    -- could otherwise read as the command having done nothing for a while.
    say("transcribing…")
    require("media").transcribe(path, opts, function(transcript, err)
      if not transcript then
        say(err or "transcription failed", vim.log.levels.ERROR)
        return
      end
      local mode = (opts and opts.output) or require("media.config").get().transcribe.output
      local ok, derr = require("media.output").deliver(path, transcript, mode)
      if not ok then
        say(derr or "could not deliver the transcript", vim.log.levels.ERROR)
        return
      end
      if mode == "sidecar" then
        say(("wrote %s"):format(require("media.output.sidecar").path(path)))
      end
    end)
    return
  end

  say("unknown action: " .. tostring(action), vim.log.levels.ERROR)
end

---@internal
---@param ctx table
---@param verb string
---@return string|nil
local function require_path(ctx, verb)
  local path = M.resolve_path(ctx.args and ctx.args.path)
  if not path then
    say(("%s: no file given, and none under the cursor"):format(verb), vim.log.levels.WARN)
    return nil
  end
  return path
end

---@internal
--- A `key=value` that has to be a positive integer, or nil when it was absent.
---@param raw string|nil
---@return integer|nil
local function positive_int(raw)
  local n = tonumber(raw)
  if not n or n < 1 then return nil end
  return math.floor(n)
end

---@return nil
function M.register()
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  if not ok then
    -- Without lib.nvim there is no composer, and a plugin that registers no
    -- command at all because an optional dependency is missing is worse than
    -- one command without tab completion.
    M.register_fallback()
    return
  end

  composer.register_type("MEDIA_PATH", {
    validate = function(raw)
      return true, raw, nil
    end,
    complete = function(arg_lead)
      return complete_media_path(arg_lead)
    end,
  })

  local path_arg = { { name = "path", type = "MEDIA_PATH", optional = true } }

  composer.verb("Media", {
    desc = "Describe or picture a media file (ffmpeg/ffprobe)",
    routes = {
      {
        path = {},
        args = path_arg,
        desc = "Describe the file  :Media [path]",
        run = function(ctx)
          local path = require_path(ctx, "Media")
          if path then M.run("probe", path) end
        end,
      },

      {
        path = { "probe" },
        args = path_arg,
        desc = "Describe the file  :Media probe [path]",
        run = function(ctx)
          local path = require_path(ctx, "Media probe")
          if path then M.run("probe", path) end
        end,
      },

      {
        path = { "frame" },
        args = path_arg,
        kv = { { key = "at", type = "STRING" }, { key = "width", type = "STRING" } },
        desc = "Poster frame  :Media frame [path] [at=10%] [width=800]",
        run = function(ctx)
          local path = require_path(ctx, "Media frame")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("frame", path, {
            -- `at` stays a string when it is not a number: "10%" and
            -- "00:01:23" are both valid offsets, and `resolve_at` is the one
            -- place that knows which is which.
            at = kv.at and (tonumber(kv.at) or kv.at) or nil,
            width = positive_int(kv.width),
          })
        end,
      },

      {
        path = { "sheet" },
        args = path_arg,
        kv = {
          { key = "rows", type = "STRING" },
          { key = "cols", type = "STRING" },
          { key = "width", type = "STRING" },
        },
        desc = "Contact sheet  :Media sheet [path] [rows=3] [cols=4] [width=1200]",
        run = function(ctx)
          local path = require_path(ctx, "Media sheet")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("sheet", path, {
            rows = positive_int(kv.rows),
            cols = positive_int(kv.cols),
            width = positive_int(kv.width),
          })
        end,
      },

      {
        path = { "waveform" },
        args = path_arg,
        kv = { { key = "width", type = "STRING" }, { key = "height", type = "STRING" } },
        desc = "Waveform picture  :Media waveform [path] [width=1200] [height=300]",
        run = function(ctx)
          local path = require_path(ctx, "Media waveform")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("waveform", path, {
            width = positive_int(kv.width),
            height = positive_int(kv.height),
          })
        end,
      },

      {
        path = { "spectrogram" },
        args = path_arg,
        kv = { { key = "width", type = "STRING" }, { key = "height", type = "STRING" } },
        desc = "Spectrogram picture  :Media spectrogram [path] [width=1200] [height=300]",
        run = function(ctx)
          local path = require_path(ctx, "Media spectrogram")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("spectrogram", path, {
            width = positive_int(kv.width),
            height = positive_int(kv.height),
          })
        end,
      },

      {
        path = { "play" },
        args = path_arg,
        desc = "Play in an external player  :Media play [path]",
        run = function(ctx)
          local path = require_path(ctx, "Media play")
          if path then M.run("play", path) end
        end,
      },

      {
        path = { "window" },
        args = path_arg,
        kv = { { key = "at", type = "STRING" }, { key = "screen", type = "STRING" } },
        desc = "Play in an mpv window  :Media window [path] [at=90] [screen=1]",
        run = function(ctx)
          local path = require_path(ctx, "Media window")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("window", path, {
            at = kv.at and (tonumber(kv.at) or kv.at) or nil,
            screen = kv.screen and tonumber(kv.screen) or nil,
          })
        end,
      },

      {
        path = { "transcribe" },
        args = path_arg,
        kv = {
          { key = "engine", type = "STRING" },
          { key = "lang", type = "STRING" },
          { key = "task", type = "STRING" },
          { key = "out", type = "STRING" },
        },
        desc = "Speech to text  :Media transcribe [path] [engine=] [lang=] [task=transcribe|translate] [out=buffer|sidecar]",
        run = function(ctx)
          local path = require_path(ctx, "Media transcribe")
          if not path then return end
          local kv = ctx.kv or {}
          M.run("transcribe", path, {
            engine = kv.engine,
            lang = kv.lang,
            task = kv.task,
            output = kv.out,
          })
        end,
      },

      {
        path = { "engines" },
        desc = "List registered transcription engines and their availability",
        run = function()
          require("media.engines").load_all()
          local registry = require("media.core.registry")
          local ids = registry.ids()
          if #ids == 0 then
            say("no transcription engines registered")
            return
          end
          local lines = {}
          for _, id in ipairs(ids) do
            local engine = registry.get(id)
            lines[#lines + 1] = ("%-14s %s"):format(
              id,
              engine_available(engine) and "available" or "unavailable"
            )
          end
          say(table.concat(lines, "\n"))
        end,
      },

      {
        path = { "cache", "clear" },
        desc = "Delete every rendered still",
        run = function()
          say(("%d cached still(s) removed"):format(require("media").clear_cache()))
        end,
      },

      {
        path = { "health" },
        desc = "Run health check",
        run = function()
          vim.cmd("checkhealth media")
        end,
      },
    },
  })
end

--- The command without lib.nvim: same subcommands, plain completion.
---@return nil
function M.register_fallback()
  vim.api.nvim_create_user_command("Media", function(cmd)
    local sub = cmd.fargs[1] or "probe"
    local path = M.resolve_path(cmd.fargs[2])
    if sub == "cache" then
      say(("%d cached still(s) removed"):format(require("media").clear_cache()))
      return
    end
    if sub == "health" then
      vim.cmd("checkhealth media")
      return
    end
    if sub == "engines" then
      require("media.engines").load_all()
      local registry = require("media.core.registry")
      local ids = registry.ids()
      if #ids == 0 then
        say("no transcription engines registered")
        return
      end
      local lines = {}
      for _, id in ipairs(ids) do
        lines[#lines + 1] = ("%-14s %s"):format(
          id,
          engine_available(registry.get(id)) and "available" or "unavailable"
        )
      end
      say(table.concat(lines, "\n"))
      return
    end
    if not path then
      say("Media: no file given, and none under the cursor", vim.log.levels.WARN)
      return
    end
    M.run(sub, path)
  end, {
    nargs = "*",
    complete = function(arg_lead, line)
      if line:match("^%s*Media%s+%S*$") then
        return vim.tbl_filter(function(name)
          return name:find(arg_lead, 1, true) == 1
        end, {
          "probe",
          "frame",
          "sheet",
          "waveform",
          "spectrogram",
          "transcribe",
          "engines",
          "play",
          "window",
          "cache",
          "health",
        })
      end
      return complete_media_path(arg_lead)
    end,
    desc = "Describe or picture a media file (ffmpeg/ffprobe)",
  })
end

return M
