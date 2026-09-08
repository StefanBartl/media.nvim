-- Everything loads, and setup() leaves the editor in the state it promises.
--
-- Last in the run order on purpose: it calls setup(), which requires the
-- binding modules that the earlier specs assert are still untouched.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  for _, name in ipairs({
    "media",
    "media.config",
    "media.config.DEFAULTS",
    "media.formats",
    "media.health",
    "media.ui",
    "media.core.bin",
    "media.core.cache",
    "media.core.frame",
    "media.core.play",
    "media.core.proc",
    "media.core.probe",
    "media.core.sheet",
    "media.bindings",
    "media.bindings.autocmds",
    "media.bindings.keymaps",
    "media.bindings.usrcmds",
  }) do
    local ok, err = pcall(require, name)
    H.ok(ok, ("%s loads: %s"):format(name, tostring(err)))
  end

  local media = require("media")
  for _, fn in ipairs({
    "setup",
    "available",
    "is_video",
    "is_audio",
    "is_media",
    "probe",
    "probed",
    "frame",
    "sheet",
    "play",
    "clear_cache",
  }) do
    H.eq(type(media[fn]), "function", "media." .. fn .. " is part of the public surface")
  end

  -- The defaults have to be usable on their own: nothing in this plugin
  -- requires setup() to have run, and a consumer that never calls it is the
  -- supported case.
  local cfg = require("media.config").get()
  H.eq(type(cfg.frame.at), "string", "a default offset exists")
  H.ok(cfg.frame.width > 0, "and a default width")
  H.ok(cfg.sheet.rows * cfg.sheet.cols > 1, "a sheet has more than one tile")
  H.ok(
    cfg.sheet.timeout_ms > cfg.timeout_ms,
    "a whole-file pass gets longer than an interactive seek"
  )

  -- Availability must answer without throwing on a machine with no ffmpeg —
  -- which is exactly what CI is.
  H.eq(type(media.available()), "boolean", "availability is answerable either way")

  -- setup() is idempotent: a reload, or a second `:Lazy reload`, must not leave
  -- two of anything behind.
  media.setup()
  media.setup({ frame = { width = 640 } })
  H.eq(require("media.config").get().frame.width, 640, "the second setup won")
  H.eq(
    require("media.config").get().frame.at,
    require("media.config.DEFAULTS").frame.at,
    "and a partial table did not erase the rest of the defaults"
  )

  H.eq(vim.fn.exists(":Media"), 2, "setup registers the command")

  -- The deep copy in config.setup: a merged table must not have written
  -- through into the module-level defaults.
  H.ok(
    require("media.config.DEFAULTS").frame.width ~= 640,
    "the defaults were not modified by a setup() call"
  )
end
