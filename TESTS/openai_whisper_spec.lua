-- openai-whisper engine: argv shape, the model/download decision, the
-- JSON-to-Transcript translation and the failure reason.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local engine = require("media.engines.openai_whisper")
  local config = require("media.config")

  H.eq(engine.id, "openai_whisper", "the id the registry keys on")

  -- ── argv ──────────────────────────────────────────────────────────────
  local argv = engine.args({
    bin = "whisper",
    wav_path = "/tmp/talk.wav",
    model = "medium",
    out_dir = "/tmp/out",
    lang = "de",
  })
  H.eq(argv[1], "whisper", "the binary first")
  H.eq(argv[2], "/tmp/talk.wav", "the input is the first positional argument")
  H.eq(argv[H.index_of(argv, "--model") + 1], "medium", "the model name reaches whisper")
  H.eq(argv[H.index_of(argv, "--output_format") + 1], "json", "JSON, which carries the segments")
  H.eq(argv[H.index_of(argv, "--output_dir") + 1], "/tmp/out", "into the private directory")
  H.eq(argv[H.index_of(argv, "--verbose") + 1], "False", "no transcript on stdout")
  H.eq(argv[H.index_of(argv, "--language") + 1], "de", "the forced language")
  H.falsy(H.index_of(argv, "--task"), "no task flag for plain transcription")
  H.falsy(H.index_of(argv, "--model_dir"), "no model dir unless configured")
  H.falsy(H.index_of(argv, "--device"), "no device unless configured")

  local full = engine.args({
    bin = "whisper",
    wav_path = "/tmp/talk.wav",
    model = "tiny",
    out_dir = "/tmp/out",
    translate = true,
    model_dir = "/models",
    device = "cpu",
  })
  H.eq(full[H.index_of(full, "--task") + 1], "translate", "translate reaches whisper's own task")
  H.eq(full[H.index_of(full, "--model_dir") + 1], "/models", "")
  H.eq(full[H.index_of(full, "--device") + 1], "cpu", "")
  H.falsy(H.index_of(full, "--language"), "no language flag means whisper detects it")

  -- ── model names map to the file whisper downloads them to ────────────
  config.setup({ transcribe = { openai_whisper = { model_dir = "/models" } } })
  H.eq(engine.checkpoint("medium"), "/models/medium.pt", "a plain name is <name>.pt")
  H.eq(engine.checkpoint("turbo"), "/models/large-v3-turbo.pt", "an alias maps to its real file")
  H.eq(engine.checkpoint("large"), "/models/large-v3.pt", "")
  H.eq(engine.checkpoint("C:/x/my.pt"), "C:/x/my.pt", "a path is its own checkpoint")

  -- ── a missing model is an error unless downloads are allowed ─────────
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  config.setup({ transcribe = { openai_whisper = { model_dir = dir } } })
  local none, err = engine.resolve_model("small")
  H.eq(none, nil, "a model that is not downloaded is not used silently")
  H.match(err, "not downloaded", "the error says why")
  H.match(err, "allow_download", "and how to allow it")
  local default_none, default_err = engine.resolve_model(nil)
  H.eq(default_none, nil, "")
  H.match(
    default_err,
    '"turbo"',
    "with no model asked for, the CLI's own default is what is checked"
  )

  vim.fn.writefile({ "x" }, dir .. "/small.pt")
  H.eq(engine.resolve_model("small"), "small", "a downloaded model is used by name")

  config.setup({ transcribe = { openai_whisper = { model_dir = dir, allow_download = true } } })
  H.eq(engine.resolve_model("medium"), "medium", "allow_download lets whisper fetch it")
  local typo, typo_err = engine.resolve_model("meduim")
  H.eq(typo, nil, "a misspelt name is not handed to whisper")
  H.match(typo_err, "unknown openai%-whisper model", "and is called unknown, not undownloaded")
  local _, path_err = engine.resolve_model(dir .. "/missing.pt")
  H.match(path_err, "model not found", "a checkpoint path must exist, download or not")

  config.setup({
    transcribe = { openai_whisper = { model_dir = dir, model = "small" } },
  })
  H.eq(engine.resolve_model(nil), "small", "the configured model is the default")
  vim.fn.delete(dir, "rf")
  config.setup({})

  -- ── JSON → Media.Transcript ───────────────────────────────────────────
  -- The shape `whisper/utils.py`'s WriteJSON writes: the whole result dict.
  local transcript = engine.from_json({
    text = " Hallo zusammen. Wie geht's?",
    language = "de",
    segments = {
      { id = 0, seek = 0, start = 0.0, ["end"] = 2.5, text = " Hallo zusammen." },
      { id = 1, seek = 0, start = 2.5, ["end"] = 4.0, text = " Wie geht's?" },
    },
  }, "medium")
  H.eq(transcript.engine, "openai_whisper", "the transcript records which engine made it")
  H.eq(transcript.model, "medium", "and with which model")
  H.eq(transcript.lang, "de", "the detected language comes through")
  H.eq(#transcript.segments, 2, "one segment per entry")
  H.eq(transcript.segments[1].e, 2.5, "times are already seconds — no ms conversion")
  H.eq(transcript.segments[2].s, 2.5, "")
  H.eq(transcript.segments[1].text, "Hallo zusammen.", "leading space trimmed")
  H.eq(transcript.text, "Hallo zusammen. Wie geht's?", "the flat text is every segment joined")

  local sparse = engine.from_json({ segments = { { text = "nur das" } } }, nil)
  H.eq(sparse.segments[1].s, 0, "a missing time falls back to zero rather than throwing")
  H.eq(#engine.from_json({}, nil).segments, 0, "no segments at all is an empty transcript")

  -- ── the reason a run failed ──────────────────────────────────────────
  H.eq(
    engine.failure_reason(
      "Skipping C:\\tmp\\x.wav due to RuntimeError: Failed to load audio: x.wav: Invalid data\n",
      "Traceback (most recent call last):\n  ...\nRuntimeError: Failed to load audio\n"
    ),
    "RuntimeError: Failed to load audio: x.wav: Invalid data",
    "the CLI's own Skipping line wins: it is the per-file failure that exits 0"
  )
  H.eq(
    engine.failure_reason(
      "",
      "usage: whisper [-h] ...\nwhisper: error: argument --model: invalid valid_model_name value: 'huge'\n"
    ),
    "argument --model: invalid valid_model_name value: 'huge'",
    "argparse's error line for a bad flag"
  )
  H.eq(
    engine.failure_reason(
      nil,
      "100%|####| 1.51G/1.51G\nTraceback (most recent call last):\n  File ...\n"
        .. "urllib.error.URLError: <urlopen error [Errno 11001] getaddrinfo failed>\n"
    ),
    "urllib.error.URLError: <urlopen error [Errno 11001] getaddrinfo failed>",
    "the last line of an uncaught traceback"
  )
  H.eq(
    engine.failure_reason("", "  3%|▎   | 12/400 [00:02<01:10]\n"),
    nil,
    "progress alone is no failure"
  )
  H.eq(engine.failure_reason(nil, nil), nil, "")

  -- ── a conda environment gets what `conda activate` would put on PATH ──
  do
    local cli = require("media.engines.whisper_cli")
    local prefix = vim.fn.tempname()
    vim.fn.mkdir(prefix .. "/conda-meta", "p")
    vim.fn.mkdir(prefix .. "/Scripts", "p")
    local in_conda = prefix .. "/Scripts/whisper.exe"
    -- `vim.fs.dirname` hands back `/` separators on Windows too.
    local np = vim.fs.normalize(prefix)
    local win = cli.conda_path(in_conda, true)
    H.eq(win[1], np, "the prefix first, as conda activates it")
    H.ok(H.index_of(win, np .. "/Library/bin"), "Library/bin, where the DLLs live")
    H.eq_list(cli.conda_path(prefix .. "/bin/whisper", false), { np .. "/bin" }, "Unix: bin")
    H.eq(#cli.conda_path("E:/plain/Scripts/whisper.exe", true), 0, "no conda-meta: nothing added")
    H.eq(#cli.conda_path("whisper", true), 0, "a bare command: nothing added")
    -- The platform's own entry: `Library/bin` on Windows, `bin` elsewhere
    -- (found by CI: the Windows-only expectation failed on Linux and macOS).
    local windows = vim.fn.has("win32") == 1
    local in_env = windows and in_conda or (prefix .. "/bin/whisper")
    if not windows then vim.fn.mkdir(prefix .. "/bin", "p") end
    local env = cli.child_env(false, in_env)
    local expected = windows and (np .. "/Library/bin") or (np .. "/bin")
    H.ok(
      env.PATH and vim.startswith(env.PATH, windows and np or expected),
      "child_env puts the environment in front of the child's PATH: " .. tostring(env.PATH)
    )
    H.ok(env.PATH:find(expected, 1, true), "including " .. expected)
    vim.fn.delete(prefix, "rf")
  end

  -- ── transcribe(): the whole process half, against a fake vim.system ───
  -- No Python on a CI runner, so `vim.system` is swapped for a double that
  -- plays the CLI: it reads `--output_dir` from the argv and writes (or does
  -- not write) `<wav stem>.json` there, then exits. Restored in every path.
  local real_system = vim.system
  local fake_ffmpeg_dir = "E:/__openai_whisper_spec__/ffmpeg/bin"
  local calls = {}
  local behaviour
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, sysopts, on_exit)
    local call = { cmd = cmd, opts = sysopts, killed = false }
    calls[#calls + 1] = call
    local out_dir = cmd[H.index_of(cmd, "--output_dir") + 1]
    local stem = vim.fn.fnamemodify(cmd[2], ":t:r")
    local obj = {
      kill = function()
        call.killed = true
        vim.schedule(function()
          on_exit({ code = 1, signal = 15, stdout = "", stderr = "" })
        end)
      end,
    }
    if behaviour == "ok" then
      vim.fn.writefile({
        vim.json.encode({
          language = "de",
          segments = { { start = 0, ["end"] = 1.5, text = " Guten Morgen." } },
        }),
      }, out_dir .. "/" .. stem .. ".json")
      vim.schedule(function()
        on_exit({ code = 0, stdout = "", stderr = "" })
      end)
    elseif behaviour == "skip" then
      vim.schedule(function()
        on_exit({
          code = 0,
          stdout = "Skipping " .. cmd[2] .. " due to RuntimeError: Failed to load audio\n",
          stderr = "Traceback (most recent call last):\n",
        })
      end)
    end -- "hang": never exits on its own; only kill() ends it
    return obj
  end

  local proc_ok, proc_err = pcall(function()
    local models = vim.fn.tempname()
    vim.fn.mkdir(models, "p")
    vim.fn.writefile({ "x" }, models .. "/tiny.pt")
    config.setup({
      bin = {
        whisper = "E:/__openai_whisper_spec__/whisper.exe",
        ffmpeg = fake_ffmpeg_dir .. "/ffmpeg.exe",
      },
      transcribe = { openai_whisper = { model_dir = models } },
    })
    require("media.core.bin").reset()

    -- A successful run: the JSON is read from the private directory.
    behaviour = "ok"
    local got, got_err
    engine.transcribe("/tmp/talk.wav", { lang = "de", model = "tiny" }, function(t, e)
      got, got_err = t, e
    end)
    vim.wait(2000, function()
      return got ~= nil or got_err ~= nil
    end, 5)
    H.eq(got_err, nil, "the run succeeded")
    H.eq(got and got.text, "Guten Morgen.", "the transcript came from <stem>.json")
    H.eq(got and got.model, "tiny", "")
    local ok_call = calls[#calls]
    local ok_dir = ok_call.cmd[H.index_of(ok_call.cmd, "--output_dir") + 1]
    H.eq(vim.uv.fs_stat(ok_dir), nil, "the private output directory is removed afterwards")
    H.match(
      ok_call.opts.env.PATH,
      "^" .. vim.pesc(vim.fs.dirname(fake_ffmpeg_dir .. "/ffmpeg.exe")),
      "ffmpeg's directory is put in front of the child's PATH"
    )
    H.eq(ok_call.opts.env.PYTHONIOENCODING, "utf-8", "UTF-8 stdio for the child")

    -- Exit 0 with no JSON: the CLI's own Skipping line is the reason.
    behaviour = "skip"
    local skip_t, skip_err = "unset", nil
    engine.transcribe("/tmp/talk.wav", { model = "tiny" }, function(t, e)
      skip_t, skip_err = t, e
    end)
    vim.wait(2000, function()
      return skip_err ~= nil
    end, 5)
    H.eq(skip_t, nil, "no transcript from a skipped file")
    H.eq(skip_err, "RuntimeError: Failed to load audio", "the reason, not 'wrote no JSON'")

    -- Cancel: the process is stopped, the callback never fires, and the
    -- directory is still cleaned up when the killed process exits.
    behaviour = "hang"
    local fired = false
    local job = engine.transcribe("/tmp/talk.wav", { model = "tiny" }, function()
      fired = true
    end)
    local hang_call = calls[#calls]
    local hang_dir = hang_call.cmd[H.index_of(hang_call.cmd, "--output_dir") + 1]
    job.cancel()
    vim.wait(200, function()
      return vim.uv.fs_stat(hang_dir) == nil
    end, 5)
    H.ok(hang_call.killed, "cancel stops the process")
    H.eq(fired, false, "and the callback never fires after it")
    H.eq(vim.uv.fs_stat(hang_dir), nil, "the output directory is removed regardless")

    vim.fn.delete(models, "rf")
  end)
  vim.system = real_system
  config.setup({})
  require("media.core.bin").reset()
  assert(proc_ok, proc_err)
end
