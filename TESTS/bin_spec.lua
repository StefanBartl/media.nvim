-- media.core.bin: the explicit-config-always-wins rule, the per-name cache
-- keyed on (name, configured value), and its reset. Uses fabricated binary
-- names throughout so a real (or missing) ffmpeg/mpv install on the machine
-- running this suite cannot change the outcome — the one exception is the
-- `available()` check at the end, which touches the real "ffmpeg"/"ffprobe"
-- cache entries and resets them back to "unlooked-up" afterwards so
-- `smoke_spec`'s own `media.available()` call still does a real, uncached
-- lookup.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local bin = require("media.core.bin")
  local config = require("media.config")

  -- ── an explicit config path is honoured even though it does not exist ──
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/does-not-exist.exe" } })
  bin.reset("mpv")
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/does-not-exist.exe",
    "an explicit config path wins over PATH/well-known lookups, existing or not"
  )

  -- ── a config change is picked up on the very next find(), no reset() ───
  -- The cache key is (name, config.get().bin[name]): a different configured
  -- value is a cache miss on its own, so a stale answer can no longer
  -- outlive the `setup()` call that changed it.
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/other.exe" } })
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/other.exe",
    "a config change invalidates the cache by itself; find() sees it immediately"
  )

  -- ── an unchanged config is still cached: repeating the same setup() does
  --    not re-derive the answer, it returns the same cached entry ─────────
  config.setup({ bin = { mpv = "E:/__media_bin_spec__/other.exe" } })
  H.eq(
    bin.find("mpv"),
    "E:/__media_bin_spec__/other.exe",
    "an identical config value is still a cache hit"
  )

  -- ── reset(name) still works, for what a config diff cannot see (PATH or
  --    an install changing under an unchanged config) ─────────────────────
  bin.reset("mpv")
  H.eq(bin.find("mpv"), "E:/__media_bin_spec__/other.exe", "reset(name) re-derives the same answer")

  -- ── a name that is neither configured, on PATH, nor in a well-known
  --    install directory resolves to nil, and stays nil on a second ask ──
  config.setup({})
  local missing = "__media_bin_spec_missing__"
  H.eq(bin.find(missing), nil, "nothing found for a name that exists nowhere")
  H.eq(
    bin.find(missing),
    nil,
    "the negative result is cached too, not re-derived as something else"
  )

  -- ── configuring a previously-missing name takes effect immediately,
  --    no reset() needed — this is the case PERF-46 was about: a user who
  --    configures `bin.ffmpeg` after an earlier failed lookup must not keep
  --    getting "not found" for the rest of the session ───────────────────
  config.setup({ bin = { [missing] = "E:/__media_bin_spec__/now-configured.exe" } })
  H.eq(
    bin.find(missing),
    "E:/__media_bin_spec__/now-configured.exe",
    "configuring a name that previously resolved to nil is seen without reset()"
  )

  -- ── reset() with no argument still clears every cached name ────────────
  bin.reset()
  H.eq(
    bin.find(missing),
    "E:/__media_bin_spec__/now-configured.exe",
    "a bare reset() re-derives the same answer for every name"
  )

  -- ── available(): true means both binaries resolved to *something*,
  --    not that either file actually exists — the same "honour the config
  --    as given" rule M.find documents ────────────────────────────────────
  bin.reset("ffmpeg")
  bin.reset("ffprobe")
  config.setup({
    bin = {
      ffmpeg = "E:/__media_bin_spec__/ffmpeg-fake.exe",
      ffprobe = "E:/__media_bin_spec__/ffprobe-fake.exe",
    },
  })
  H.eq(bin.available(), true, "available() trusts an explicit config path without stat'ing it")

  -- ── Python console tools are also looked for in Python's Scripts
  --    directories, newest version first; other names are not ───────────
  H.eq(#bin.python_scripts("ffmpeg"), 0, "ffmpeg is not a Python tool: no Scripts dirs probed")
  local fake_localapp = vim.fn.tempname()
  vim.fn.mkdir(fake_localapp .. "/Programs/Python/Python310", "p")
  vim.fn.mkdir(fake_localapp .. "/Programs/Python/Python312", "p")
  local store_pkg = fake_localapp
    .. "/Packages/PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0/LocalCache/local-packages/Python312"
  vim.fn.mkdir(store_pkg, "p")
  vim.fn.mkdir(
    fake_localapp .. "/Packages/SomethingElse_123/LocalCache/local-packages/Python312",
    "p"
  )
  local saved_localapp = vim.env.LOCALAPPDATA
  vim.env.LOCALAPPDATA = fake_localapp
  local probed = bin.python_scripts("whisper")
  vim.env.LOCALAPPDATA = saved_localapp
  vim.fn.delete(fake_localapp, "rf")
  local newer =
    H.index_of(probed, fake_localapp .. "/Programs/Python/Python312/Scripts/whisper.exe")
  local older =
    H.index_of(probed, fake_localapp .. "/Programs/Python/Python310/Scripts/whisper.exe")
  H.ok(newer, "the per-user python.org install's Scripts dir is probed")
  H.ok(older and newer < older, "the newest Python version is tried first")
  H.ok(
    H.index_of(probed, store_pkg .. "/Scripts/whisper.exe"),
    "the Microsoft Store Python's user Scripts dir is probed"
  )
  for _, p in ipairs(probed) do
    H.falsy(p:find("SomethingElse", 1, true), "other Store packages are not: " .. p)
  end
  H.ok(
    H.index_of(probed, (vim.uv.os_homedir() or "") .. "/.local/bin/whisper"),
    "pipx / pip --user on Unix is probed"
  )

  -- ── an active venv / conda environment comes first; a conda base last ─
  local saved_venv, saved_conda = vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX
  vim.env.VIRTUAL_ENV = "E:/__bin_spec__/venv"
  vim.env.CONDA_PREFIX = "E:/__bin_spec__/conda-env"
  local envs = bin.python_scripts("whisper")
  vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = saved_venv, saved_conda
  H.eq(
    envs[1],
    "E:/__bin_spec__/venv/Scripts/whisper.exe",
    "the active venv is tried first (Windows layout)"
  )
  H.eq(envs[2], "E:/__bin_spec__/venv/bin/whisper", "and its Unix layout")
  H.eq(
    envs[3],
    "E:/__bin_spec__/conda-env/Scripts/whisper.exe",
    "then the active conda environment"
  )
  H.match(envs[#envs], "/miniforge3/bin/whisper$", "a never-activated conda base comes last")
  H.ok(
    H.index_of(envs, (vim.uv.os_homedir() or "") .. "/miniconda3/Scripts/whisper.exe"),
    "miniconda's base is among them"
  )

  -- ── version order, not byte order: 3.13 is newer than 3.9 ─────────────
  do
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/Programs/Python/Python39", "p")
    vim.fn.mkdir(root .. "/Programs/Python/Python313", "p")
    local saved = vim.env.LOCALAPPDATA
    vim.env.LOCALAPPDATA = root
    local list = bin.python_scripts("whisper")
    vim.env.LOCALAPPDATA = saved
    vim.fn.delete(root, "rf")
    local v313 = H.index_of(list, root .. "/Programs/Python/Python313/Scripts/whisper.exe")
    local v39 = H.index_of(list, root .. "/Programs/Python/Python39/Scripts/whisper.exe")
    H.ok(v313 and v39 and v313 < v39, "Python313 is tried before Python39")
  end

  -- ── an unset or empty variable never becomes a drive-root root ───────
  -- (`"" .. "/Programs/Python"` is the root of the current drive on Windows,
  -- a directory any local user may create.) Asserted on the roots, before
  -- the scan: a scanned candidate only appears when the directory exists.
  do
    local saved_l, saved_a = vim.env.LOCALAPPDATA, vim.env.APPDATA
    local root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/Python/Python312", "p")
    vim.env.LOCALAPPDATA, vim.env.APPDATA = nil, root
    local roots = bin.python_roots()
    local only_user = bin.python_scripts("whisper")
    vim.env.LOCALAPPDATA, vim.env.APPDATA = "", ""
    local empty_roots = bin.python_roots()
    local list = bin.candidates("whisper")
    vim.env.LOCALAPPDATA, vim.env.APPDATA = saved_l, saved_a
    vim.fn.delete(root, "rf")
    H.eq(roots.programs, nil, "unset LOCALAPPDATA: no python.org root")
    H.eq(roots.store, nil, "and no Store root")
    H.ok(
      H.index_of(only_user, root .. "/Python/Python312/Scripts/whisper.exe"),
      "APPDATA's root is still walked when LOCALAPPDATA is missing"
    )
    H.eq(empty_roots.programs, nil, "an empty variable is no root either")
    H.eq(empty_roots.user, nil, "")
    for _, p in ipairs(list) do
      H.falsy(
        p:match("^/Programs")
          or p:match("^/Python")
          or p:match("^/Packages")
          or p:match("^/Microsoft"),
        "no candidate under the drive root from an empty variable: " .. p
      )
    end
  end

  -- ── the active venv comes before the installer shims ─────────────────
  do
    local outer_venv = vim.env.VIRTUAL_ENV
    vim.env.VIRTUAL_ENV = "E:/__bin_spec__/venv"
    local list = bin.candidates("whisper")
    vim.env.VIRTUAL_ENV = outer_venv
    local venv = H.index_of(list, "E:/__bin_spec__/venv/Scripts/whisper.exe")
    local choco = H.index_of(list, "C:/ProgramData/chocolatey/bin/whisper.exe")
    H.ok(venv and choco and venv < choco, "VIRTUAL_ENV wins over a global shim")
  end

  -- ── a venv activated after a cached miss is seen without reset() ─────
  do
    local saved = {
      PATH = vim.env.PATH,
      LOCALAPPDATA = vim.env.LOCALAPPDATA,
      APPDATA = vim.env.APPDATA,
      VIRTUAL_ENV = vim.env.VIRTUAL_ENV,
      CONDA_PREFIX = vim.env.CONDA_PREFIX,
    }
    local empty = vim.fn.tempname()
    vim.fn.mkdir(empty, "p")
    local venv = vim.fn.tempname()
    vim.fn.mkdir(venv .. "/Scripts", "p")
    vim.fn.mkdir(venv .. "/bin", "p")
    vim.fn.writefile({ "x" }, venv .. "/Scripts/whisper.exe")
    vim.fn.writefile({ "x" }, venv .. "/bin/whisper")
    local ok_run, err_run = pcall(function()
      -- Nothing on PATH and no Python roots: a real install cannot answer.
      vim.env.PATH = empty
      vim.env.LOCALAPPDATA, vim.env.APPDATA = empty, empty
      vim.env.VIRTUAL_ENV, vim.env.CONDA_PREFIX = nil, nil
      config.setup({})
      bin.reset("whisper")
      H.eq(bin.find("whisper"), nil, "no whisper anywhere: a cached miss")
      vim.env.VIRTUAL_ENV = venv
      local found = bin.find("whisper")
      H.ok(
        found == venv .. "/Scripts/whisper.exe" or found == venv .. "/bin/whisper",
        "the newly active venv is seen without reset(): " .. tostring(found)
      )
    end)
    for k, v in pairs(saved) do
      vim.env[k] = v
    end
    bin.reset("whisper")
    vim.fn.delete(empty, "rf")
    vim.fn.delete(venv, "rf")
    assert(ok_run, err_run)
  end

  -- Leave no trace for later specs/consumers: real, uncached lookups again.
  bin.reset("ffmpeg")
  bin.reset("ffprobe")
  bin.reset(missing)
  config.setup({})
end
