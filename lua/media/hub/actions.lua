---@module 'media.hub.actions'
---@brief What you can do to a row, and doing it to several rows at once.
---@description
--- The action table from ROADMAP.md's "The hub", and the batch flow beside it.
---
--- **Actions are offered per kind *and* per availability, and the second half
--- is the interesting one.** A row whose tool is not installed still shows its
--- action, with the reason attached — the same principle `images.ocr` applies
--- to a missing tesseract language. Hiding it would answer "what can I do right
--- now" when the question a dashboard is asked is "what is possible here";
--- nobody ever learned that media.nvim could OCR a screenshot from a menu that
--- silently did not mention it.
---
--- **One progress handle over the whole batch, not one per file.** The shape
--- is `language.translate.files`' own (`process`, a `step()` recursion,
--- `update{ text, current, total }`, one `finish`) — and the ratio is honest
--- here in a way it is not inside a single transcription: *files done of files
--- asked* has a real denominator, where "38% through this audio" would be a
--- guess. The same reasoning that kept a percentage off the single-run
--- indicator is what puts one on this one.
---
--- **The handle lives with the caller.** This module reports which file it is
--- on and nothing more, exactly as `media.core.dispatcher` reports its phases;
--- the dashboard owns the `lib.nvim.progress` handle, because the dashboard is
--- the UI. See `media.hub.text`'s header for the same split one level down.

local M = {}

--- One thing that can be done to one row.
---@class Media.Hub.Action
---@field id string
---@field label string        # what a menu calls it
---@field mode string|nil     # the `out=` mode it delivers to, when it produces text
---@field opts table|nil      # extra options for `media.hub.text.run`
---@field needs_text boolean  # whether it runs the text pipeline at all

---@internal
--- Every action, in menu order, keyed by the kinds it applies to.
---
--- `needs_text = false` marks the three that are navigation rather than work:
--- they are instant, they cannot fail interestingly, and a batch of them makes
--- no sense — which is why `M.batchable` exists.
---@type table<string, Media.Hub.Action[]>
local TABLE = {
  image = {
    { id = "ocr_sidecar", label = "OCR → sidecar", mode = "sidecar", needs_text = true },
    { id = "ocr_buffer", label = "OCR → buffer", mode = "buffer", needs_text = true },
  },
  pdf = {
    {
      id = "text_sidecar",
      label = "Extract text → sidecar",
      mode = "sidecar",
      needs_text = true,
    },
    { id = "text_buffer", label = "Extract text → buffer", mode = "buffer", needs_text = true },
  },
  audio = {
    {
      id = "transcribe_sidecar",
      label = "Transcribe → sidecar",
      mode = "sidecar",
      needs_text = true,
    },
    {
      id = "transcribe_buffer",
      label = "Transcribe → buffer",
      mode = "buffer",
      needs_text = true,
    },
    { id = "srt", label = "Transcribe → .srt", mode = "srt", needs_text = true },
    { id = "vtt", label = "Transcribe → .vtt", mode = "vtt", needs_text = true },
    {
      id = "translate",
      label = "Transcribe + translate to English",
      mode = "sidecar",
      opts = { task = "translate" },
      needs_text = true,
    },
  },
}

-- Video is audio's table verbatim: both reach the same dispatcher, and a
-- second copy is how the two drift apart the first time one gains an action.
TABLE.video = TABLE.audio

---@internal
--- The actions that are navigation rather than work, offered for every kind.
---@type Media.Hub.Action[]
local COMMON = {
  { id = "open_text", label = "Open the existing text", needs_text = false },
  { id = "open_source", label = "Open the source file", needs_text = false },
  { id = "describe", label = "Describe it (ffprobe)", needs_text = false },
}

--- Every action for `kind`, in menu order.
---
--- The list does not depend on anything being installed — availability is
--- `M.availability`'s answer, attached per entry by whatever draws the menu.
---@param kind Media.Hub.Kind
---@return Media.Hub.Action[]
function M.list(kind)
  local out = {}
  for _, action in ipairs(TABLE[kind] or {}) do
    out[#out + 1] = action
  end
  for _, action in ipairs(COMMON) do
    out[#out + 1] = action
  end
  return out
end

--- The action `<CR>` runs on a row — the obvious thing, and never wasted work.
---
--- Missing or stale means the text is worth making; `ok` means it is already
--- there and the obvious thing is to read it. That asymmetry is the point: a
--- `<CR>` that re-transcribed a file whose transcript was current would spend
--- minutes to produce what was already on disk, and a `<CR>` that only ever
--- opened would make the dashboard a list you cannot act on.
---@param entry Media.Hub.Entry
---@return Media.Hub.Action|nil
function M.default_for(entry)
  if entry.status == "ok" then
    for _, action in ipairs(COMMON) do
      if action.id == "open_text" then return action end
    end
    return nil
  end

  local list = TABLE[entry.kind]
  -- The first entry of each kind's table is its sidecar route, deliberately:
  -- a batch of buffers is a stack of windows nobody asked for, and the
  -- sidecar is the one that leaves something behind.
  return list and list[1] or nil
end

--- Whether `action` can run on `kind` right now, with the reason when not.
---
--- The navigation actions are always available: opening a file needs no tool,
--- and `describe` degrades to its own message when ffprobe is missing.
---@param action Media.Hub.Action
---@param kind Media.Hub.Kind
---@return Media.Hub.Tool
function M.availability(action, kind)
  if not action.needs_text then return { ok = true, tool = "" } end
  return require("media.hub.text").tool(kind)
end

---@internal
--- The kind-agnostic actions, for a marked set that spans several kinds.
---
--- `media.hub.text` routes per file, so these run the right tool on each row
--- without caring what it is — which is the whole point of `:Media text`, one
--- level up.
---@type Media.Hub.Action[]
local MIXED = {
  { id = "text_sidecar", label = "Text → sidecar", mode = "sidecar", needs_text = true },
  { id = "text_buffer", label = "Text → buffer", mode = "buffer", needs_text = true },
}

--- The actions valid for **every** kind in `entries`.
---
--- **A marked set may span kinds, and the per-kind table does not.** Taking
--- the first row's kind and offering its table — which is what this did first —
--- puts "Transcribe → .srt" in front of a set holding a screenshot, and the
--- screenshot then fails at delivery with "out=srt is not available for this
--- kind". The menu offered something that could not work, and the reader found
--- out after the run.
---
--- One kind is its own table, unchanged. Several kinds get the two routes that
--- mean the same thing everywhere: to a sidecar, or to a buffer. Subtitles are
--- not among them, because a set containing an image has no honest `.srt`.
---@param entries Media.Hub.Entry[]
---@return Media.Hub.Action[]
---@return Media.Hub.Kind|nil kind  # nil when the set spans more than one
function M.for_entries(entries)
  local kind = entries[1] and entries[1].kind or nil
  for _, entry in ipairs(entries) do
    if entry.kind ~= kind then return MIXED, nil end
  end
  return kind and M.list(kind) or {}, kind
end

--- Whether `action` makes sense over several rows at once.
---
--- Only the ones that do work. "Open the source file" over twelve rows is
--- twelve windows, which is not a batch — it is a mistake with a progress bar
--- on it.
---@param action Media.Hub.Action
---@return boolean
function M.batchable(action)
  return action.needs_text == true
end

--- Run `action` over `entries`, one after another.
---
--- **Sequential on purpose.** Each of these is a whole external process —
--- ffmpeg then whisper.cpp for a video — and running twelve at once would put
--- twelve of them on the machine competing for the same cores. Slower in wall
--- time, and the editor unusable while it happens.
---
--- `on_step` is called *before* each file, with the ratio a caller shows; the
--- handle stops the run after the item currently in flight, which is as
--- precise as cancellation can be without abandoning work already paid for.
--- Failures do not stop the batch: a file that cannot be read is one row's
--- problem, and eleven transcripts are worth more than an error message.
---@param entries Media.Hub.Entry[]
---@param action Media.Hub.Action
---@param on_step fun(index: integer, total: integer, entry: Media.Hub.Entry): nil
---@param on_done fun(done: integer, failures: { name: string, err: string }[], cancelled: boolean): nil
---@return { cancel: fun(): nil }
function M.run_batch(entries, action, on_step, on_done)
  local total = #entries
  local index = 0
  local done = 0
  ---@type { name: string, err: string }[]
  local failures = {}
  local cancelled = false
  ---@type Media.Transcribe.Handle|nil
  local current = nil

  local function step()
    if cancelled then
      on_done(done, failures, true)
      return
    end

    index = index + 1
    if index > total then
      on_done(done, failures, false)
      return
    end

    local entry = entries[index]
    on_step(index, total, entry)

    local hub = require("media.hub.text")
    current = hub.run(entry.path, action.opts, function(result, err)
      current = nil
      if not result then
        failures[#failures + 1] = { name = entry.name, err = err or "failed" }
      else
        local ok, derr = hub.deliver(entry.path, result, action.mode)
        if ok then
          done = done + 1
        else
          failures[#failures + 1] = { name = entry.name, err = derr or "could not deliver" }
        end
      end
      -- Scheduled rather than called straight through: a batch of cache hits
      -- would otherwise recurse once per file on the same stack, and a
      -- thousand-file scan is a thousand frames deep.
      vim.schedule(step)
    end)
  end

  vim.schedule(step)

  return {
    cancel = function()
      if cancelled then return end
      cancelled = true
      -- Stop the run in flight too, where there is one to stop. OCR and PDF
      -- extraction hand back nothing, so those finish and the batch ends
      -- after them.
      if current then pcall(current.cancel) end
    end,
  }
end

return M
