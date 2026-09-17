---@module 'media.hub.dashboard'
---@brief One list across image, pdf, audio and video — and whether their text
---is there.
---@description
--- The view over `media.hub.scan` (ROADMAP.md, "The hub"). Its row format is
--- the roadmap's own, and the one column that justifies the whole thing is the
--- last one: **stale** is a distinct state from **missing**, because missing is
--- a job not yet done and stale is a file on disk quietly answering questions
--- about a version of the source that no longer exists.
---
--- **A third marker for stale, which the roadmap's sketch did not have.** It
--- showed `— transcript: stale` beside `— transcript: missing`, distinguished
--- only by the word. The whole argument for the column is that stale is the
--- dangerous one, and a reader scanning forty rows scans *markers*, not words.
--- So: `✓` fine, `—` missing, `!` stale.
---
--- **The detail column is filled after the list is drawn, not before.**
--- `media.hub.scan` deliberately starts no processes — five hundred files
--- would be five hundred `ffprobe`s before a single row appeared. So the list
--- goes up at once with whatever is already cached (`media.probed`), and a
--- bounded number of probes then fill the rest in and redraw. A dashboard that
--- is instantly there and completes itself beats one that is correct in four
--- seconds.
---
--- **Not every kind can have a detail, and none is invented.** `ffprobe`
--- answers for audio, video and images — a duration for the first two,
--- dimensions for the third. A PDF's page count needs `pdfinfo`, which this
--- plugin does not own and will not shell out to behind pdfport's back; that
--- column stays blank rather than guessed.

local M = {}

--- How many files the view will probe to fill in the detail column.
---
--- The bound exists for the case the cap in `media.hub.scan` exists for: a
--- scan that turned out to cover a home directory. Fifty is well past a screen
--- of rows, which is what a reader can act on before they filter.
local PROBE_LIMIT = 50

---@internal
--- The marker and the words for one row's status.
---@type table<Media.Hub.Status, { marker: string, suffix: string|nil }>
local STATUS = {
  ok = { marker = "✓", suffix = nil },
  missing = { marker = "—", suffix = "missing" },
  stale = { marker = "!", suffix = "stale" },
  none = { marker = " ", suffix = nil },
}

--- How long ago a sidecar was written, as a row says it.
---
--- Rounded down to the largest unit that still reads as a number: "3 days old"
--- is what a reader wants from this column, and "3 days, 4 hours and 12
--- minutes old" is three more facts than the decision needs. Under a minute is
--- "just now" rather than "0 minutes old", which reads as broken.
---@param seconds integer|nil
---@return string|nil
function M.age(seconds)
  if type(seconds) ~= "number" or seconds < 0 then return nil end
  if seconds < 60 then return "just now" end

  ---@param n integer
  ---@param unit string
  ---@return string
  local function plural(n, unit)
    return ("%d %s%s old"):format(n, unit, n == 1 and "" or "s")
  end

  if seconds < 3600 then return plural(math.floor(seconds / 60), "minute") end
  if seconds < 86400 then return plural(math.floor(seconds / 3600), "hour") end
  return plural(math.floor(seconds / 86400), "day")
end

--- The middle column for one entry, from what is *already* known.
---
--- Synchronous and process-free by contract: `media.probed` answers from the
--- probe cache or answers nil, and never blocks. A row with nothing to say
--- gets an empty string rather than a placeholder — an aligned column of
--- `?`s is noise, and the reader can see the gap perfectly well.
---@param entry Media.Hub.Entry
---@return string
function M.detail(entry)
  local ok, media = pcall(require, "media")
  if not ok or type(media.probed) ~= "function" then return "" end

  local probe = media.probed(entry.path)
  if not probe then return "" end

  -- **Zero is not a measurement, and in Lua it is not falsy either.** A file
  -- ffprobe could open but not understand comes back with a probe whose
  -- numbers are all zero, and `probe.width and probe.height` happily lets that
  -- through — the column then reads `0x0`, which looks like a fact. Found
  -- against a truncated PNG, 2026-09-17.
  if entry.kind == "audio" or entry.kind == "video" then
    if not probe.duration or probe.duration <= 0 then return "" end
    return require("media.ui").duration(probe.duration)
  end

  if entry.kind == "image" then
    local w, h = probe.width, probe.height
    if not w or not h or w <= 0 or h <= 0 then return "" end
    return ("%dx%d"):format(w, h)
  end

  return ""
end

--- The status half of one row: the marker, the verb, and what is wrong.
---@param entry Media.Hub.Entry
---@return string
function M.status_text(entry)
  local state = STATUS[entry.status] or STATUS.none
  local verb = require("media.hub.kinds").verb(entry.kind)
  if not verb then return "" end

  if entry.status == "ok" then
    local age = M.age(entry.age)
    return age and ("%s %s (%s)"):format(state.marker, verb, age)
      or ("%s %s"):format(state.marker, verb)
  end

  return ("%s %s: %s"):format(state.marker, verb, state.suffix or entry.status)
end

--- Every entry as one aligned line.
---
--- Pure, and it takes the details as data rather than fetching them, for two
--- reasons: the alignment is the part worth asserting and it should be
--- assertable without a filesystem, and the async fill redraws by calling this
--- again with a fuller table rather than by patching lines in place.
---@param entries Media.Hub.Entry[]
---@param details table<string, string>|nil  # path → detail column, default `M.detail`
---@return string[]
function M.rows(entries, details)
  details = details or {}

  local kind_w, name_w, detail_w = 0, 0, 0
  local cells = {}
  for i, entry in ipairs(entries) do
    local detail = details[entry.path] or ""
    cells[i] = { kind = entry.kind, name = entry.name, detail = detail }
    kind_w = math.max(kind_w, vim.fn.strdisplaywidth(entry.kind))
    name_w = math.max(name_w, vim.fn.strdisplaywidth(entry.name))
    detail_w = math.max(detail_w, vim.fn.strdisplaywidth(detail))
  end

  ---@param s string
  ---@param width integer
  ---@return string
  local function pad(s, width)
    -- `strdisplaywidth`, not `#`: a path with an umlaut in it is fewer columns
    -- than bytes, and padding by byte count tilts every row after it.
    return s .. (" "):rep(math.max(0, width - vim.fn.strdisplaywidth(s)))
  end

  local lines = {}
  for i, entry in ipairs(entries) do
    local cell = cells[i]
    lines[i] = ("  %s  %s  %s  %s")
      :format(
        pad(cell.kind, kind_w),
        pad(cell.name, name_w),
        pad(cell.detail, detail_w),
        M.status_text(entry)
      )
      :gsub("%s+$", "")
  end
  return lines
end

--- What the window is called: the root, and how much is in it.
---
--- The root is stated here rather than on every row, which is why
--- `media.hub.scan` hands back relative names — repeating the project
--- directory forty times buys nothing but width.
---@param root string
---@param entries Media.Hub.Entry[]
---@return string
function M.title(root, entries)
  local stale, missing = 0, 0
  for _, entry in ipairs(entries) do
    if entry.status == "stale" then
      stale = stale + 1
    elseif entry.status == "missing" then
      missing = missing + 1
    end
  end

  local counts = { ("%d file%s"):format(#entries, #entries == 1 and "" or "s") }
  -- Stale first, and named in the title, because it is the one a reader would
  -- otherwise have to go looking for. Missing is visible from the list itself.
  if stale > 0 then counts[#counts + 1] = ("%d stale"):format(stale) end
  if missing > 0 then counts[#counts + 1] = ("%d missing"):format(missing) end

  return (" media: %s — %s "):format(vim.fn.fnamemodify(root, ":~"), table.concat(counts, ", "))
end

---@internal
--- Replace a scratch buffer's contents, cursor kept where it was.
---
--- The buffer is `nofile` and not modifiable by the reader, so writing to it
--- means turning that off and back on around the write. Keeping the cursor
--- matters more than it sounds: the redraw lands while somebody is reading,
--- and a list that jumps back to row one every time a probe answers is worse
--- than one that never fills in at all.
---@param bufnr integer
---@param winid integer
---@param lines string[]
---@return nil
local function redraw(bufnr, winid, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end
  local row = nil
  if vim.api.nvim_win_is_valid(winid) then row = vim.api.nvim_win_get_cursor(winid)[1] end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  if row and vim.api.nvim_win_is_valid(winid) then
    pcall(vim.api.nvim_win_set_cursor, winid, { math.min(row, math.max(1, #lines)), 0 })
  end
end

---@internal
--- Probe up to `PROBE_LIMIT` entries and redraw as the answers arrive.
---
--- Fire-and-forget, and every callback checks the window is still there: a
--- reader who closes the dashboard while this runs must not have a probe
--- redraw a buffer that is gone. Only kinds `ffprobe` can answer for — a PDF's
--- page count is `pdfinfo`'s, which this plugin does not own.
---@param entries Media.Hub.Entry[]
---@param details table<string, string>
---@param bufnr integer
---@param winid integer
---@return nil
local function fill_details(entries, details, bufnr, winid)
  local ok, media = pcall(require, "media")
  if not ok or type(media.probe) ~= "function" then return end

  local started = 0
  for _, entry in ipairs(entries) do
    if started >= PROBE_LIMIT then break end
    local probeable = entry.kind == "audio" or entry.kind == "video" or entry.kind == "image"
    if probeable and details[entry.path] == "" then
      started = started + 1
      media.probe(entry.path, function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        -- Re-read through `M.detail` rather than using the probe directly:
        -- one place decides what a kind's detail column says, and it is the
        -- same one the first draw went through.
        details[entry.path] = M.detail(entry)
        redraw(bufnr, winid, M.rows(entries, details))
      end)
    end
  end
end

---@internal
---@param message string
---@param level integer|nil
---@return nil
local function say(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "media.nvim" })
end

---@internal
--- Bind the reader's keys to the row under the cursor.
---
--- Deliberately few. Acting on a row — running the OCR, the extraction, the
--- transcription, over one file or a marked batch — is the hub's next stage;
--- what these four do is get you to the file or to the text that already
--- exists, which is the half a list is useless without.
---@param bufnr integer
---@param winid integer
---@param state { entries: Media.Hub.Entry[], scope: string|nil, arg: string|nil }
---@return nil
local function bind(bufnr, winid, state)
  ---@return Media.Hub.Entry|nil
  local function current()
    if not vim.api.nvim_win_is_valid(winid) then return nil end
    return state.entries[vim.api.nvim_win_get_cursor(winid)[1]]
  end

  ---@param lhs string
  ---@param desc string
  ---@param fn fun(entry: Media.Hub.Entry): nil
  local function on(lhs, desc, fn)
    vim.keymap.set("n", lhs, function()
      local entry = current()
      if entry then fn(entry) end
    end, { buffer = bufnr, nowait = true, silent = true, desc = desc })
  end

  on("<CR>", "media: open this file's text", function(entry)
    if entry.status == "missing" then
      say(
        ("no %s yet — `:Media text %s` makes one"):format(
          require("media.hub.kinds").verb(entry.kind) or "text",
          vim.fn.fnamemodify(entry.path, ":~:.")
        )
      )
      return
    end
    if not entry.sidecar then
      say("nothing here turns this kind of file into text")
      return
    end
    -- A stale sidecar opens anyway, with the warning: it is still the text
    -- that is there, and the reader asked to see it. Refusing would hide the
    -- very thing the column exists to point at.
    if entry.status == "stale" then
      say("this text is older than the file it describes", vim.log.levels.WARN)
    end
    vim.cmd("close")
    vim.cmd.edit(vim.fn.fnameescape(entry.sidecar))
  end)

  on("gf", "media: open the source file", function(entry)
    vim.cmd("close")
    vim.cmd.edit(vim.fn.fnameescape(entry.path))
  end)

  on("p", "media: describe this file", function(entry)
    require("media.ui").show_probe(entry.path)
  end)

  vim.keymap.set("n", "r", function()
    vim.cmd("close")
    M.open(state.scope, state.arg)
  end, { buffer = bufnr, nowait = true, silent = true, desc = "media: rescan" })
end

--- Open the dashboard over `scope`.
---
--- The list is on screen before anything is probed; see the module header for
--- why that order is the right one.
---@param scope Media.Hub.Scope|nil  # default "cwd"
---@param arg string|nil
---@return nil
function M.open(scope, arg)
  local scan = require("media.hub.scan")
  local root, err = scan.root(scope, arg)
  if not root then
    say(err or "could not resolve that scope", vim.log.levels.ERROR)
    return
  end

  local entries = scan.scan(scope, arg)
  if not entries then
    say("could not scan " .. root, vim.log.levels.ERROR)
    return
  end

  if #entries == 0 then
    -- An answer, not an empty window: "nothing here" and "the scan failed"
    -- look identical in a blank list, and only one of them is true.
    say(("no images, PDFs, audio or video under %s"):format(vim.fn.fnamemodify(root, ":~")))
    return
  end

  ---@type table<string, string>
  local details = {}
  for _, entry in ipairs(entries) do
    details[entry.path] = M.detail(entry)
  end

  local ok, make_scratch = pcall(require, "lib.nvim.window.make_scratch")
  if not ok then
    -- Without lib.nvim there is no float to put this in, and a notify with
    -- forty rows in it is not a dashboard — but it is the whole answer, which
    -- is better than refusing to have looked.
    say(table.concat(M.rows(entries, details), "\n"))
    return
  end

  local winid, bufnr = make_scratch({
    lines = M.rows(entries, details),
    filetype = "media-dashboard",
    title = M.title(root, entries),
    title_pos = "center",
    width = 0.8,
    height = 0.7,
    wo = { wrap = false, cursorline = true },
    nice_quit = true,
  })
  if not (winid and bufnr) then return end

  bind(bufnr, winid, { entries = entries, scope = scope, arg = arg })
  fill_details(entries, details, bufnr, winid)
end

return M
