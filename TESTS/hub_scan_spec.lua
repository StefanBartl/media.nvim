-- media.hub.scan: the three scopes, the walk, and the three-way status.
--
-- The status is the half worth a real filesystem, so this spec builds one in
-- `tempname()` and takes it down again: "stale" is a *timestamp* relationship
-- and stubbing fs_stat would only assert that the stub was written the way the
-- code reads it. The walk and the scope resolution are pure enough to check
-- against the same tree.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch

---@param H table
return function(H)
  local scan = require("media.hub.scan")
  local uv = vim.uv or vim.loop

  -- ── the three words of scope ───────────────────────────────────────────
  local cwd_root = scan.root("cwd")
  H.ok(cwd_root and cwd_root ~= "", "cwd resolves without an argument")
  H.eq(scan.root(), cwd_root, "and is the default when no scope is named")

  local missing_root, path_err = scan.root("path")
  H.eq(missing_root, nil, "the path scope without a directory is an error")
  H.match(path_err, "needs a directory", "that says what was missing")

  local bad_root, bad_err = scan.root("path", "/definitely/not/a/directory/here")
  H.eq(bad_root, nil, "and so is a path that is not a directory")
  H.match(bad_err, "not a directory", "")

  local unknown, unknown_err = scan.root("everything")
  H.eq(unknown, nil, "an unknown scope is rejected rather than guessed at")
  H.match(unknown_err, "cfile, cwd or path", "naming the three that would have worked")

  -- ── a real tree ────────────────────────────────────────────────────────
  local root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(root .. "/talks", "p")
  vim.fn.mkdir(root .. "/node_modules/whatever", "p")
  vim.fn.mkdir(root .. "/.git", "p")
  vim.fn.mkdir(root .. "/skipme", "p")

  ---@param rel string
  ---@param when integer|nil  # mtime to force, in seconds
  local function write(rel, when)
    local fd = assert(io.open(root .. "/" .. rel, "w"))
    fd:write("x")
    fd:close()
    if when then uv.fs_utime(root .. "/" .. rel, when, when) end
  end

  local ok, err = pcall(function()
    local now = os.time()

    write("talks/standup.mp4", now - 1000)
    write("talks/retro.mp4", now - 1000)
    write("talks/retro.mp4.transcript.md", now - 500) -- newer than the source: ok
    write("talks/keynote.mp4", now - 100)
    write("talks/keynote.mp4.transcript.md", now - 900) -- older: stale
    write("notes.m4a", now - 1000)
    write("spec.pdf", now - 1000)
    write("error.png", now - 1000)
    write("init.lua", now - 1000)
    write("node_modules/whatever/bundle.mp4", now - 1000)
    write(".git/config.mp4", now - 1000)
    write("skipme/hidden.mp4", now - 1000)

    -- ── the walk ────────────────────────────────────────────────────────
    local walked = scan.walk(root, { "skipme" }, 20000)
    ---@param needle string
    ---@return boolean
    local function walked_has(needle)
      for _, p in ipairs(walked) do
        if p:find(needle, 1, true) then return true end
      end
      return false
    end

    H.ok(walked_has("talks/standup.mp4"), "the walk descends into subdirectories")
    H.falsy(walked_has("node_modules"), "and never into node_modules — the cap would die there")
    H.falsy(walked_has(".git/"), "nor into .git")
    H.falsy(walked_has("skipme/"), "nor into a configured exclusion")
    H.ok(walked_has("init.lua"), "the walk itself does not filter by kind — scan does")

    H.falsy(
      walked_has("retro.mp4.transcript.md"),
      "a sidecar is skipped: listed, the next scan would offer to extract text from it"
    )

    local sorted = true
    for i = 2, #walked do
      if walked[i - 1] > walked[i] then sorted = false end
    end
    H.ok(sorted, "results come back sorted, so two runs draw the same list")

    -- The cap is a quiet stop, not an error — what was found is still useful.
    local capped = scan.walk(root, nil, 3)
    H.ok(#capped <= 3, "the entry cap holds")
    H.ok(type(capped) == "table", "and stopping returns the partial list rather than failing")

    -- ── the three-way status, which is the whole point of the column ────
    local status, sidecar, age = scan.status(root .. "/talks/standup.mp4")
    H.eq(status, "missing", "no sidecar at all is `missing` — a job not yet done")
    H.eq(sidecar, root .. "/talks/standup.mp4.transcript.md", "named so a row can say where")
    H.eq(age, nil, "a file that does not exist has no age")

    status, sidecar, age = scan.status(root .. "/talks/retro.mp4")
    H.eq(status, "ok", "a sidecar written after its source is current")
    H.eq(sidecar, root .. "/talks/retro.mp4.transcript.md", "still named, so a row can open it")
    H.ok(type(age) == "number" and age >= 400, "and reports how long ago, for the row")

    status = scan.status(root .. "/talks/keynote.mp4")
    H.eq(
      status,
      "stale",
      "a source edited after its sidecar is STALE, not missing and not ok — the state that silently answers questions about a version that is gone"
    )

    status, sidecar = scan.status(root .. "/init.lua")
    H.eq(status, "none", "a kind with no text operation is not waiting for anything")
    H.eq(sidecar, nil, "")
    H.falsy(status == "missing", "`none` and `missing` are different answers")

    -- ── the scan, end to end ────────────────────────────────────────────
    local entries, scan_err = scan.scan("path", root)
    H.eq(scan_err, nil, "")
    H.ok(entries ~= nil, "the scan produced rows")

    local by_name = {}
    for _, e in ipairs(entries) do
      by_name[e.name] = e
    end

    H.eq(by_name["init.lua"], nil, "`other` never becomes a row — this is a media hub")
    H.ok(by_name["notes.m4a"], "audio is listed")
    H.ok(by_name["spec.pdf"], "so is a PDF")
    H.ok(by_name["error.png"], "and an image")

    H.eq(by_name["talks/standup.mp4"].kind, "video", "each row carries its kind")
    H.eq(by_name["talks/standup.mp4"].status, "missing", "and its status")
    H.eq(by_name["talks/keynote.mp4"].status, "stale", "")
    H.eq(by_name["talks/retro.mp4"].status, "ok", "")

    H.eq(
      by_name["talks/standup.mp4"].path,
      root .. "/talks/standup.mp4",
      "the path stays absolute — it is what an action acts on"
    )
    H.match(
      by_name["talks/standup.mp4"].name,
      "^talks/",
      "while the name is relative to the root, which the header states once"
    )

    -- ── the relative name ───────────────────────────────────────────────
    H.eq(scan.relative("/a/b/c.mp4", "/a/b"), "c.mp4", "")
    H.eq(scan.relative("/a/b/c.mp4", "/a/b/"), "c.mp4", "a trailing slash on the root is fine")
    H.eq(
      scan.relative("/elsewhere/c.mp4", "/a/b"),
      "/elsewhere/c.mp4",
      "a path outside the root keeps its full name rather than being mangled"
    )
  end)

  vim.fn.delete(root, "rf")
  H.ok(ok, "hub_scan_spec: " .. tostring(err))
end
