-- media.hub.dashboard: the row format, the markers, and the age column.
--
-- The formatting half only, and deliberately: an off-by-one in a column width
-- tilts every row after it and is invisible in a screenshot taken of one row,
-- while the window itself is `lib.nvim.window.make_scratch` doing what it
-- already does. `rows` takes its details as data for exactly this reason —
-- assertable with no filesystem, no ffprobe and no float.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local dashboard = require("media.hub.dashboard")

  -- ── the age column ──────────────────────────────────────────────────────
  H.eq(dashboard.age(0), "just now", "under a minute is not '0 minutes old', which reads as broken")
  H.eq(dashboard.age(59), "just now", "")
  H.eq(dashboard.age(60), "1 minute old", "and the singular is singular")
  H.eq(dashboard.age(120), "2 minutes old", "")
  H.eq(dashboard.age(3600), "1 hour old", "")
  H.eq(dashboard.age(7200), "2 hours old", "")
  H.eq(dashboard.age(86400), "1 day old", "")
  H.eq(dashboard.age(3 * 86400), "3 days old", "the roadmap's own example")
  H.eq(dashboard.age(nil), nil, "nothing written means nothing to say about when")
  H.eq(dashboard.age(-5), nil, "")

  -- Rounded down to the largest unit that still reads as a number: three more
  -- facts than the decision needs is not more useful.
  H.eq(dashboard.age(86400 + 3600 * 4), "1 day old", "the remainder is dropped, not spelled out")

  -- ── the status half of a row ────────────────────────────────────────────
  -- Three markers, not two. The roadmap's sketch distinguished stale from
  -- missing by the word alone; the whole argument for this column is that
  -- stale is the dangerous one, and a reader scanning forty rows scans
  -- markers.
  H.eq(
    dashboard.status_text({ kind = "video", status = "missing" }),
    "— transcript: missing",
    "missing is a job not yet done"
  )
  H.eq(
    dashboard.status_text({ kind = "audio", status = "stale" }),
    "! transcript: stale",
    "stale gets its own marker — it is the state that silently answers questions about a version that is gone"
  )
  H.eq(
    dashboard.status_text({ kind = "video", status = "ok", age = 3 * 86400 }),
    "✓ transcript (3 days old)",
    ""
  )
  H.eq(
    dashboard.status_text({ kind = "video", status = "ok" }),
    "✓ transcript",
    "a sidecar with no readable mtime still reports as present"
  )
  H.eq(
    dashboard.status_text({ kind = "image", status = "missing" }),
    "— ocr: missing",
    "each kind is named by its own verb, because they are different operations"
  )
  H.eq(dashboard.status_text({ kind = "pdf", status = "missing" }), "— text: missing", "")
  H.eq(
    dashboard.status_text({ kind = "other", status = "none" }),
    "",
    "a kind with no text operation says nothing rather than an empty marker"
  )

  -- ── the detail column, and the zero that is not a measurement ───────────
  -- The defect this closes: a file ffprobe can open but not understand comes
  -- back with every number zero, and `probe.width and probe.height` lets that
  -- through because 0 is truthy in Lua. The column then read `0x0`, which
  -- looks like a fact. Found against a truncated PNG.
  local real_media = package.loaded["media"]
  ---@type table<string, table>
  local probes = {}
  package.loaded["media"] = {
    probed = function(p)
      return probes[p]
    end,
  }

  local detail_ok, detail_err = pcall(function()
    probes["/r/broken.png"] = { width = 0, height = 0 }
    H.eq(
      dashboard.detail({ path = "/r/broken.png", kind = "image" }),
      "",
      "zero dimensions are not dimensions"
    )

    probes["/r/good.png"] = { width = 1920, height = 1080 }
    H.eq(dashboard.detail({ path = "/r/good.png", kind = "image" }), "1920x1080", "")

    probes["/r/broken.mp4"] = { duration = 0 }
    H.eq(
      dashboard.detail({ path = "/r/broken.mp4", kind = "video" }),
      "",
      "and a zero duration is not a duration"
    )

    probes["/r/good.mp4"] = { duration = 7.04 }
    H.eq(dashboard.detail({ path = "/r/good.mp4", kind = "video" }), "0:07", "")

    H.eq(
      dashboard.detail({ path = "/r/never-probed.mp4", kind = "video" }),
      "",
      "a file nothing has probed yet has nothing to say — and asking must not start a process"
    )

    probes["/r/spec.pdf"] = { width = 612, height = 792 }
    H.eq(
      dashboard.detail({ path = "/r/spec.pdf", kind = "pdf" }),
      "",
      "a PDF's page count is pdfinfo's answer, not ffprobe's — the column stays blank rather than guessed"
    )
  end)

  package.loaded["media"] = real_media
  H.ok(detail_ok, "detail column: " .. tostring(detail_err))

  -- ── the rows, and their alignment ───────────────────────────────────────
  ---@type Media.Hub.Entry[]
  local entries = {
    {
      path = "/r/talks/standup.mp4",
      name = "talks/standup.mp4",
      kind = "video",
      status = "missing",
      sidecar = "/r/talks/standup.mp4.transcript.md",
    },
    {
      path = "/r/notes.m4a",
      name = "notes.m4a",
      kind = "audio",
      status = "stale",
      sidecar = "/r/notes.m4a.transcript.md",
      age = 7200,
    },
    {
      path = "/r/error.png",
      name = "error.png",
      kind = "image",
      status = "ok",
      sidecar = "/r/error.png.ocr.md",
      age = 3 * 86400,
    },
    {
      path = "/r/spec.pdf",
      name = "spec.pdf",
      kind = "pdf",
      status = "missing",
      sidecar = "/r/spec.pdf.text.md",
    },
  }

  local lines = dashboard.rows(entries, {
    ["/r/talks/standup.mp4"] = "14:32",
    ["/r/notes.m4a"] = "6:44",
    ["/r/error.png"] = "1920x1080",
  })

  H.eq(#lines, 4, "one line per entry")
  H.match(lines[1], "video", "")
  H.match(lines[1], "talks/standup%.mp4", "the name is the relative one the scan produced")
  H.match(lines[1], "14:32", "the detail column carries what was known")
  H.match(lines[1], "— transcript: missing", "")
  H.match(lines[2], "! transcript: stale", "")
  H.match(lines[3], "✓ ocr %(3 days old%)", "")

  -- Alignment: every status marker starts in the same column, which is the
  -- one thing that makes forty rows scannable and the one thing a `#`-based
  -- pad silently breaks on a path with an umlaut in it.
  ---@param line string
  ---@return integer|nil
  local function marker_col(line)
    local at = line:find("[✓—!]")
    return at and vim.fn.strdisplaywidth(line:sub(1, at - 1)) or nil
  end
  local first = marker_col(lines[1])
  H.ok(first ~= nil, "every row has a marker")
  for i = 2, #lines do
    H.eq(marker_col(lines[i]), first, ("row %d's marker lines up with row 1's"):format(i))
  end

  -- The widest name sets the column, and `pdf` being shorter than `video`
  -- must not pull its row left.
  H.ok(
    lines[4]:find("pdf   ", 1, true) ~= nil or lines[4]:find("pdf  ", 1, true) ~= nil,
    "a short kind is padded to the widest one"
  )

  H.falsy(
    lines[1]:match("%s$"),
    "trailing whitespace is trimmed — it is invisible and it is diff noise"
  )

  -- A missing detail leaves a gap rather than a placeholder: an aligned column
  -- of `?`s is noise, and the reader can see the gap perfectly well.
  local sparse = dashboard.rows(entries, {})
  H.eq(#sparse, 4, "")
  H.falsy(sparse[1]:find("?", 1, true), "nothing is invented for a detail that is not known yet")
  H.match(sparse[1], "— transcript: missing", "and the status still lines up")

  H.eq_list(dashboard.rows({}, {}), {}, "no entries is no rows, not an error")

  -- ── the title states the root once, and counts what matters ─────────────
  local title = dashboard.title("/r", entries)
  H.match(title, "4 files", "")
  H.match(
    title,
    "1 stale",
    "stale is named in the title — it is the one a reader would go looking for"
  )
  H.match(title, "2 missing", "")

  H.match(dashboard.title("/r", { entries[1] }), "1 file", "the singular is singular here too")
  H.falsy(
    dashboard.title("/r", { entries[3] }):find("stale"),
    "a clean scan does not advertise a count of zero"
  )
end
