-- faster-whisper engine (whisper-ctranslate2): argv, the model/cache
-- decision, the failure reason and a whole run against a fake vim.system.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local engine = require("media.engines.faster_whisper")
  local config = require("media.config")

  H.eq(engine.id, "faster_whisper", "the id the registry keys on")

  -- ── argv ──────────────────────────────────────────────────────────────
  local argv = engine.args({
    bin = "whisper-ctranslate2",
    wav_path = "/tmp/talk.wav",
    model = "medium",
    out_dir = "/tmp/out",
    lang = "de",
    offline = true,
  })
  H.eq(argv[2], "/tmp/talk.wav", "the input is the first positional argument")
  H.eq(argv[H.index_of(argv, "--model") + 1], "medium", "a model name goes to --model")
  H.eq(argv[H.index_of(argv, "--output_format") + 1], "json", "")
  H.eq(argv[H.index_of(argv, "--output_dir") + 1], "/tmp/out", "")
  H.eq(argv[H.index_of(argv, "--verbose") + 1], "False", "")
  H.eq(argv[H.index_of(argv, "--language") + 1], "de", "")
  H.eq(
    argv[H.index_of(argv, "--local_files_only") + 1],
    "True",
    "downloads off: the tool itself is told not to fetch"
  )
  H.falsy(H.index_of(argv, "--task"), "")

  local dir_argv = engine.args({
    bin = "whisper-ctranslate2",
    wav_path = "/tmp/talk.wav",
    model = "C:/models/my-ct2",
    out_dir = "/tmp/out",
    translate = true,
    model_dir = "/hf",
    device = "cpu",
  })
  H.eq(
    dir_argv[H.index_of(dir_argv, "--model_directory") + 1],
    "C:/models/my-ct2",
    "a model directory goes to --model_directory"
  )
  H.falsy(H.index_of(dir_argv, "--model"), "and not to --model")
  H.eq(dir_argv[H.index_of(dir_argv, "--task") + 1], "translate", "")
  H.eq(dir_argv[H.index_of(dir_argv, "--model_dir") + 1], "/hf", "")
  H.eq(dir_argv[H.index_of(dir_argv, "--device") + 1], "cpu", "")
  H.falsy(H.index_of(dir_argv, "--local_files_only"), "downloads allowed: no offline flag")

  -- ── model names → Hugging Face cache entries ──────────────────────────
  config.setup({ transcribe = { faster_whisper = { model_dir = "/hf" } } })
  H.eq(engine.cache_entry("medium"), "/hf/models--Systran--faster-whisper-medium", "")
  H.eq(
    engine.cache_entry("turbo"),
    "/hf/models--mobiuslabsgmbh--faster-whisper-large-v3-turbo",
    "turbo is mobiuslabs' conversion"
  )
  H.eq(engine.cache_entry("large"), "/hf/models--Systran--faster-whisper-large-v3", "large is v3")
  H.eq(engine.cache_entry("meduim"), nil, "an unknown name has no entry")

  local hub = vim.fn.tempname()
  local snap = hub .. "/models--Systran--faster-whisper-small/snapshots/abc123"
  vim.fn.mkdir(snap, "p")
  vim.fn.writefile({ "x" }, snap .. "/model.bin")
  -- A download that was cut off: blobs and refs, no snapshot with model.bin.
  vim.fn.mkdir(hub .. "/models--Systran--faster-whisper-medium/blobs", "p")
  vim.fn.writefile({ "x" }, hub .. "/models--Systran--faster-whisper-medium/blobs/f.incomplete")
  -- A Transformers checkpoint in the same shared cache: not this CLI's.
  vim.fn.mkdir(hub .. "/models--openai--whisper-small/snapshots/s", "p")
  config.setup({ transcribe = { faster_whisper = { model_dir = hub } } })
  H.eq(engine.resolve_model(nil), "small", "no model asked for: the CLI default, downloaded")
  local partial, partial_err = engine.resolve_model("medium")
  H.eq(partial, nil, "a cut-off download is not a downloaded model")
  H.match(partial_err, "not downloaded yet", "")
  H.eq_list(
    engine.cached_models(),
    { "small" },
    "only complete entries of this CLI's own repositories are listed"
  )

  -- ── the Hugging Face cache location, in huggingface_hub's order ──────
  do
    local saved = {}
    local keys = { "HF_HUB_CACHE", "HUGGINGFACE_HUB_CACHE", "HF_HOME", "XDG_CACHE_HOME" }
    for _, k in ipairs(keys) do
      saved[k] = vim.env[k]
      vim.env[k] = nil
    end
    config.setup({})
    local home = vim.uv.os_homedir() or ""
    H.eq(engine.cache_dir(), home .. "/.cache/huggingface/hub", "the default")
    vim.env.XDG_CACHE_HOME = "/xdg"
    H.eq(engine.cache_dir(), "/xdg/huggingface/hub", "XDG_CACHE_HOME moves the HF home")
    vim.env.HF_HOME = "~/hf"
    H.eq(engine.cache_dir(), home .. "/hf/hub", "HF_HOME wins over XDG, with ~ expanded")
    vim.env.HUGGINGFACE_HUB_CACHE = "/old-hub"
    H.eq(engine.cache_dir(), "/old-hub", "the older hub variable wins over HF_HOME")
    vim.env.HF_HUB_CACHE = "/new-hub"
    H.eq(engine.cache_dir(), "/new-hub", "HF_HUB_CACHE wins over everything")
    config.setup({ transcribe = { faster_whisper = { model_dir = "/configured" } } })
    H.eq(engine.cache_dir(), "/configured", "the configured model_dir wins over the environment")
    for _, k in ipairs(keys) do
      vim.env[k] = saved[k]
    end
    config.setup({ transcribe = { faster_whisper = { model_dir = hub } } })
  end

  -- ── device: only the CLI's own choices ───────────────────────────────
  config.setup({ transcribe = { faster_whisper = { model_dir = hub, device = "mps" } } })
  H.match(
    engine.device_error(),
    "must be one of auto, cpu, cuda",
    "a torch-only device is caught early"
  )
  config.setup({ transcribe = { faster_whisper = { model_dir = hub, device = "cuda" } } })
  H.eq(engine.device_error(), nil, "")
  config.setup({ transcribe = { faster_whisper = { model_dir = hub } } })
  H.eq(engine.resolve_model("large"), nil, "large-v3 is not downloaded")
  local _, missing_err = engine.resolve_model("large")
  H.match(missing_err, "not downloaded yet", "")
  H.match(missing_err, '"large%-v3"', "the error names the CLI's own name for it")
  local _, typo_err = engine.resolve_model("meduim")
  H.match(typo_err, "unknown faster%-whisper model", "a typo is called unknown")
  local _, dir_err = engine.resolve_model(hub .. "/no-model-here")
  H.match(dir_err, "no model.bin", "a model directory must hold model.bin")

  config.setup({ transcribe = { faster_whisper = { model_dir = hub, allow_download = true } } })
  H.eq(engine.resolve_model("large"), "large-v3", "allow_download: the neutral name, mapped")

  -- ── the reason a run failed ──────────────────────────────────────────
  H.eq(
    engine.failure_reason(
      "",
      "Error: Unable to process file: x.wav\nException Type: RuntimeError\n"
        .. "Exception Message: Invalid data found when processing input\nTraceback:\n..."
    ),
    "RuntimeError: Invalid data found when processing input",
    "the per-file failure the CLI catches (exit 0)"
  )
  H.eq(
    engine.failure_reason("error: Unable to open file 'model.bin' in model 'x'\n", ""),
    "Unable to open file 'model.bin' in model 'x'",
    "a model that cannot be loaded (stdout)"
  )
  H.eq(
    engine.failure_reason(
      "",
      "whisper-ctranslate2: error: argument --model: invalid choice: 'large'\n"
    ),
    "argument --model: invalid choice: 'large'",
    "argparse"
  )
  local offline = engine.failure_reason(
    "",
    "Traceback (most recent call last):\n"
      .. "huggingface_hub.errors.LocalEntryNotFoundError: Cannot find an appropriate cached snapshot\n"
  )
  H.match(offline, "allow_download = true", "the offline refusal points at the setting")
  H.match(offline, "LocalEntryNotFoundError", "and still carries the original line")
  H.eq(engine.failure_reason("Detected language 'German'\n", "  5%|5 | 3/60\n"), nil, "")

  -- ── transcribe(): a whole run against a fake vim.system ───────────────
  local real_system = vim.system
  local calls = {}
  local behaviour
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, sysopts, on_exit)
    local call = { cmd = cmd, opts = sysopts, killed = false }
    calls[#calls + 1] = call
    local out_dir = cmd[H.index_of(cmd, "--output_dir") + 1]
    local stem = vim.fn.fnamemodify(cmd[2], ":t:r")
    if behaviour == "ok" then
      vim.fn.writefile({
        vim.json.encode({
          text = " Servus.",
          language = "de",
          segments = { { id = 1, start = 0.5, ["end"] = 2, text = " Servus." } },
        }),
      }, out_dir .. "/" .. stem .. ".json")
      -- From a genuine fast event context, as `vim.system`'s `on_exit`
      -- really is: anything in the engine's exit path that touches
      -- `vim.fn` raises E5560 here rather than passing silently.
      local check = vim.uv.new_check()
      check:start(function()
        check:stop()
        check:close()
        call.fast = vim.in_fast_event()
        on_exit({ code = 0, stdout = "", stderr = "" })
      end)
    elseif behaviour == "loadfail" then
      vim.schedule(function()
        on_exit({
          code = 1,
          stdout = "error: Unable to open file 'model.bin' in model 'C:/hf/x'\n",
          stderr = "",
        })
      end)
    elseif behaviour == "skip" then
      vim.schedule(function()
        on_exit({
          code = 0,
          stdout = "",
          stderr = "Error: Unable to process file: x\nException Type: ValueError\nException Message: bad\n",
        })
      end)
    end
    return {
      kill = function()
        call.killed = true
        vim.schedule(function()
          on_exit({ code = 1, signal = 15, stdout = "", stderr = "" })
        end)
      end,
    }
  end

  local run_ok, run_err = pcall(function()
    config.setup({
      bin = { ["whisper-ctranslate2"] = "E:/__faster_whisper_spec__/whisper-ctranslate2.exe" },
      transcribe = { faster_whisper = { model_dir = hub } },
    })
    require("media.core.bin").reset()

    behaviour = "ok"
    local got, got_err
    engine.transcribe("/tmp/talk.wav", { lang = "de" }, function(t, e)
      got, got_err = t, e
    end)
    vim.wait(2000, function()
      return got ~= nil or got_err ~= nil
    end, 5)
    H.eq(got_err, nil, "the run succeeded")
    H.eq(got and got.text, "Servus.", "read from <stem>.json")
    H.eq(got and got.engine, "faster_whisper", "")
    H.eq(got and got.segments[1].s, 0.5, "seconds, as for openai-whisper")
    local ok_call = calls[#calls]
    local ok_dir = ok_call.cmd[H.index_of(ok_call.cmd, "--output_dir") + 1]
    H.eq(vim.uv.fs_stat(ok_dir), nil, "the private directory is removed")
    H.ok(H.index_of(ok_call.cmd, "--local_files_only"), "offline by default")
    H.eq(ok_call.opts.env.PATH, nil, "no PATH change: faster-whisper does not need ffmpeg")
    H.eq(ok_call.fast, true, "the exit path really ran in a fast event context, and survived it")

    behaviour = "loadfail"
    local load_err
    engine.transcribe("/tmp/talk.wav", {}, function(_, e)
      load_err = e
    end)
    vim.wait(2000, function()
      return load_err ~= nil
    end, 5)
    H.eq(
      load_err,
      "Unable to open file 'model.bin' in model 'C:/hf/x'",
      "a non-zero exit reports stdout's error: line, not just the exit code"
    )

    behaviour = "skip"
    local skip_err
    engine.transcribe("/tmp/talk.wav", {}, function(_, e)
      skip_err = e
    end)
    vim.wait(2000, function()
      return skip_err ~= nil
    end, 5)
    H.eq(skip_err, "ValueError: bad", "exit 0 without JSON reports the caught exception")

    behaviour = "hang"
    local fired = false
    local job = engine.transcribe("/tmp/talk.wav", {}, function()
      fired = true
    end)
    local hang_call = calls[#calls]
    local hang_dir = hang_call.cmd[H.index_of(hang_call.cmd, "--output_dir") + 1]
    job.cancel()
    vim.wait(200, function()
      return vim.uv.fs_stat(hang_dir) == nil
    end, 5)
    H.ok(hang_call.killed, "cancel stops the process")
    H.eq(fired, false, "and nothing calls back")
    H.eq(vim.uv.fs_stat(hang_dir), nil, "the directory is removed regardless")

    -- A missing model never starts a process.
    local before = #calls
    local miss_err
    engine.transcribe("/tmp/talk.wav", { model = "medium" }, function(_, e)
      miss_err = e
    end)
    vim.wait(500, function()
      return miss_err ~= nil
    end, 5)
    H.match(miss_err, "not downloaded yet", "")
    H.eq(#calls, before, "no process for a model that is not there")
  end)
  vim.system = real_system
  vim.fn.delete(hub, "rf")
  config.setup({})
  require("media.core.bin").reset()
  assert(run_ok, run_err)
end
