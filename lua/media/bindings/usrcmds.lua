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
--- `m:ss`, for the elapsed clock on the transcription indicator.
---@param seconds number
---@return string
local function elapsed(seconds)
  local whole = math.max(0, math.floor(seconds))
  return ("%d:%02d"):format(math.floor(whole / 60), whole % 60)
end

---@internal
--- What to say while a given step of a run is under way.
---
--- Present tense and named after the step, because the reader is looking at
--- this *during* the wait it describes, not afterwards.
---@type table<Media.Transcribe.Phase, string>
local PHASE_TEXT = {
  normalize = "extracting audio",
  transcribe = "transcribing",
}

---@internal
--- The indicator for one transcription run.
---
--- **This is the command's job, not the dispatcher's.** `media.core.dispatcher`
--- reports which step it is on and nothing more, so a headless consumer
--- (`hover.nvim` asking for a transcript in the background) does not inherit a
--- float somebody else's `:Media transcribe` wanted. The UI lives here,
--- where the UI is the whole point.
---
--- **No percentage, deliberately.** whisper.cpp reports no progress of its
--- own, and a figure derived from the audio duration would be calibrated to
--- whichever machine, model and thread count measured it — a wrong percentage
--- is worse than none, because it is the one a reader plans around. What is
--- shown instead is true without qualification: which step, which engine, and
--- how long it has been running.
---
--- Returns `nil` when lib.nvim is not installed. Every call site guards on it;
--- the work itself does not depend on an indicator existing.
---
--- `initial` is what it says before the first phase is reported — and for OCR
--- and PDF extraction it is all it ever says, because those have no phases to
--- report. They keep the indicator anyway: the 150 ms `lib.nvim.progress`
--- waits before rendering means a fast one never flashes, and a scan of a
--- two-hundred-page document is not fast.
---@param initial string
---@return { phase: fun(info: Media.Transcribe.Progress): nil, finish: fun(text: string|nil): nil, on_cancel: fun(fn: fun(): nil): nil }|nil
local function start_progress(initial)
  local ok, progress = pcall(require, "lib.nvim.progress")
  if not ok then return nil end

  local handle = progress.create({
    title = "[media]",
    style = require("media.config").get().progress_style or "auto",
  })

  local uv = vim.uv or vim.loop
  local started = uv.now()
  local text = initial

  ---@return nil
  local function render()
    handle:update({ text = ("%s — %s"):format(text, elapsed((uv.now() - started) / 1000)) })
  end

  -- At once, before any timer or phase: `lib.nvim.progress` renders whatever
  -- the handle holds when its 150 ms delay elapses, and without this that is
  -- an empty string. A route with no phases to report (OCR, PDF extraction)
  -- would otherwise show a bare "[media]" until the first second ticked.
  render()

  -- One second, because that is the resolution of what it displays. A faster
  -- tick would redraw the same string.
  local timer = uv.new_timer()
  if timer then timer:start(1000, 1000, vim.schedule_wrap(render)) end

  ---@return nil
  local function stop_timer()
    if not timer then return end
    timer:stop()
    if not uv.is_closing(timer) then timer:close() end
    timer = nil
  end

  return {
    phase = function(info)
      text = PHASE_TEXT[info.phase] or "working"
      -- The engine's id is worth the width only on the step it is spending
      -- the minutes on; during WAV extraction it is ffmpeg's work, not its.
      if info.phase == "transcribe" and info.engine then
        text = ("%s with %s"):format(text, info.engine)
      end
      render()
    end,
    finish = function(message)
      stop_timer()
      handle:finish(message)
    end,
    on_cancel = function(fn)
      handle:on_cancel(function()
        stop_timer()
        fn()
      end)
    end,
  }
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
---@param action "probe"|"frame"|"sheet"|"waveform"|"spectrogram"|"text"|"transcribe"|"play"|"window"
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

  if action == "text" then
    -- **The kind-agnostic verb, and the reason this plugin is called `media`.**
    -- One thing to remember; `media.hub.text` picks the tool. Everything the
    -- transcribe route below learned the hard way applies here too: reject a
    -- bad `out=` and an absent tool *before* the run, show an indicator while
    -- it works, and report the outcome exactly once.
    local hub = require("media.hub.text")
    local kinds = require("media.hub.kinds")
    local kind = kinds.of(path)

    -- Said with the fix, not just the fact. "images.nvim is not installed" on
    -- its own leaves the reader to work out that OCR is where it lives.
    local tool = hub.tool(kind)
    if not tool.ok then
      say(
        tool.fix and ("%s — %s"):format(tool.reason, tool.fix) or (tool.reason or "cannot run"),
        vim.log.levels.WARN
      )
      return
    end

    local mode = (opts and opts.output) or require("media.config").get().transcribe.output
    local modes = hub.modes(kind)
    if not vim.tbl_contains(modes, mode) then
      -- Per kind, not one global list: subtitles need timestamps, so `srt` is
      -- a real answer for a video and a meaningless one for a screenshot.
      -- The kind in brackets rather than after an article: "a image" is what
      -- an article in a format string gets you the first time a kind is added
      -- that does not take "a".
      say(
        ("out=%s is not available for this kind (%s) — expected one of %s"):format(
          tostring(mode),
          kind,
          table.concat(modes, ", ")
        ),
        vim.log.levels.ERROR
      )
      return
    end

    local labels = {
      image = "reading the image",
      pdf = "extracting text",
      audio = "transcribing",
      video = "transcribing",
    }
    local progress = start_progress(labels[kind] or "working")
    if not progress then say((labels[kind] or "working") .. "…") end

    local job = hub.run(
      path,
      vim.tbl_extend("force", opts or {}, {
        on_phase = progress and progress.phase or nil,
      }),
      function(result, err)
        if not result then
          if progress then progress.finish("failed") end
          say(err or "could not turn this file into text", vim.log.levels.ERROR)
          return
        end
        local ok, derr = hub.deliver(path, result, mode)
        if not ok then
          if progress then progress.finish("failed") end
          say(derr or "could not deliver the text", vim.log.levels.ERROR)
          return
        end
        local written = hub.written_path(path, kind, mode)
        local done = written and ("wrote " .. written) or ("%s: done"):format(kinds.verb(kind))
        if progress then
          progress.finish(done)
        elseif written then
          say(done)
        end
      end
    )

    -- Only the transcription route hands one back — OCR and PDF extraction
    -- offer nothing to cancel, and `hub.run` says so by answering nil rather
    -- than inventing a `cancel()` that does nothing.
    if progress and job then
      progress.on_cancel(function()
        job.cancel()
        say("cancelled")
      end)
    end
    return
  end

  if action == "transcribe" then
    local output = require("media.output")
    local mode = (opts and opts.output) or require("media.config").get().transcribe.output

    -- **Before the run, not after it.** A rejected `out=` used to be found by
    -- `output.deliver`, which is minutes later — the reader waits out a whole
    -- transcription to be told about a typo they made before it started.
    if not output.is_mode(mode) then
      say(
        ("unknown out=%s — expected one of %s"):format(
          tostring(mode),
          table.concat(output.MODES, ", ")
        ),
        vim.log.levels.ERROR
      )
      return
    end

    -- Transcription is minutes, not seconds (ROADMAP.md's "Risks and known
    -- traps"), and a run used to say "transcribing…" once and then go silent
    -- for all of them. `progress` is the live indicator; the notify stays as
    -- the fallback for an install without lib.nvim, so the command is never
    -- completely mute.
    local progress = start_progress("transcribing")
    if not progress then say("transcribing…") end

    local job = require("media").transcribe(
      path,
      vim.tbl_extend("force", opts or {}, {
        on_phase = progress and progress.phase or nil,
      }),
      function(transcript, err)
        -- A failure goes through **both** channels, unlike the success above:
        -- the indicator says the run ended badly and the notify carries the
        -- reason at ERROR level, because a float that closes itself is not an
        -- acceptable home for the only account of why something failed.
        if not transcript then
          if progress then progress.finish("failed") end
          say(err or "transcription failed", vim.log.levels.ERROR)
          return
        end
        local ok, derr = output.deliver(path, transcript, mode)
        if not ok then
          if progress then progress.finish("failed") end
          say(derr or "could not deliver the transcript", vim.log.levels.ERROR)
          return
        end
        -- Every mode that produces a file says which one, and `written_path`
        -- is the only thing that knows the mapping — a buffer answers nil and
        -- is its own confirmation.
        --
        -- Said once, through whichever channel exists: the indicator carries
        -- the completion message when there is one, and the notify is the
        -- fallback when there is not. `replacer.nvim` reports the same way
        -- (`h:finish("128 matches in 19 files")`, no second notification) —
        -- reported twice, the `notify` style prints the same line under two
        -- different prefixes.
        local written = output.written_path(path, mode)
        local done = written and ("wrote " .. written) or "transcribed"
        if progress then
          progress.finish(done)
        elseif written then
          say(done)
        end
      end
    )

    -- **The run is now abortable, and it was not before.** `transcribe`
    -- returned a cancellable handle from the day it was written and this
    -- command dropped it, so an hour of audio started by accident ran to the
    -- end with no way to stop it. `progress_style = "float"` is the style
    -- that offers the key (focus it, `<Esc>`); the others report only.
    if progress then
      progress.on_cancel(function()
        job.cancel()
        say("transcription cancelled")
      end)
    end
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
        path = { "text" },
        args = path_arg,
        kv = { { key = "out", type = "STRING" } },
        desc = "Anything to text  :Media text [path] [out=buffer|sidecar|srt|vtt]",
        run = function(ctx)
          local path = require_path(ctx, "Media text")
          if not path then return end
          M.run("text", path, { output = (ctx.kv or {}).out })
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
        desc = "Speech to text  :Media transcribe [path] [engine=] [lang=] [task=transcribe|translate] [out=buffer|sidecar|srt|vtt]",
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
          "text",
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
