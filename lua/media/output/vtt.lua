---@module 'media.output.vtt'
---@brief WebVTT (`.vtt`) — the subtitle format a browser reads.
---@description
--- The other half of phase 1 (ROADMAP.md, "Transcription"), and the sibling of
--- `media.output.srt`: same segments, same cue preparation
--- (`media.core.segments.cues`), two formats that differ in four small places
--- and are wrong in exactly the same way when one of them is copied from the
--- other.
---
--- **The four differences, all of them here:** a `WEBVTT` header line, a full
--- stop instead of a comma in the timestamp, no cue index, and — the one that
--- is easy not to know about — cue text that is *markup*.

local M = {}

local SUFFIX = ".vtt"

--- Where this writes for `path`. Same convention as `media.output.srt.path`,
--- and for the same reason.
---@param path string
---@return string
function M.path(path)
  return path .. SUFFIX
end

--- `HH:MM:SS.mmm` — WebVTT's timestamp, with a full stop where SubRip has a
--- comma. `media.output.srt.timestamp` has the note on why these two are
--- written out twice rather than shared.
---
--- The hours field is always present. WebVTT permits the short `MM:SS.mmm`
--- form below an hour, but "the specification permits" and "every player
--- accepts" are different statements, and the long form is valid in both.
---@param seconds number|nil
---@return string
function M.timestamp(seconds)
  local ms = math.floor(math.max(0, tonumber(seconds) or 0) * 1000 + 0.5)
  return ("%02d:%02d:%02d.%03d"):format(
    math.floor(ms / 3600000),
    math.floor(ms % 3600000 / 60000),
    math.floor(ms % 60000 / 1000),
    ms % 1000
  )
end

--- Cue text with WebVTT's markup characters neutralised.
---
--- **A WebVTT cue is markup, and a SubRip cue is not** — this function has no
--- counterpart in `media.output.srt`, which is the whole reason the two
--- serialisers are separate modules. A cue carries `<i>`, `<c.classname>` and
--- `<00:00:01.000>` timestamp tags, so a transcript containing a `<` opens a
--- tag that swallows everything up to the next `>`; a speaker saying "less
--- than" and a transcriber writing it as a symbol is all it takes.
---
--- Ampersands are replaced first. The other way round, the `&` this function
--- itself writes would be escaped again on the following pass and every entity
--- would reach the file as `&amp;lt;`.
---
--- **This also disarms `-->`, which is the reason it matters most.** WebVTT's
--- parser treats a line containing `-->` as a timing line and starts a new cue
--- there, so a transcript with an arrow in it shifts every cue after it —
--- silently, and only in a player. Escaping `>` turns it into `--&gt;` before
--- a parser ever sees it, so no separate rule is needed for it.
---@param text string|nil
---@return string
function M.escape(text)
  local s = tostring(text or "")
  s = s:gsub("&", "&amp;")
  s = s:gsub("<", "&lt;")
  s = s:gsub(">", "&gt;")
  return s
end

--- One transcript as a WebVTT document.
---
--- Pure and public for the same reason `media.output.srt.serialize` is.
---
--- There is no index line: WebVTT's optional cue identifier is a *name* a
--- stylesheet can select on, not SubRip's running number, and writing one
--- there because the sibling format has one is how a cue ends up identified as
--- "3".
---@param transcript Media.Transcript
---@return string
function M.serialize(transcript)
  local cues = require("media.core.segments").cues(transcript and transcript.segments or {})

  -- The header, then the blank line that separates it from the first cue.
  -- Without that blank line the file is not WebVTT at all: the header block
  -- runs on and the first cue is read as part of it.
  local lines = { "WEBVTT", "" }
  for _, cue in ipairs(cues) do
    lines[#lines + 1] = ("%s --> %s"):format(M.timestamp(cue.s), M.timestamp(cue.e))
    lines[#lines + 1] = M.escape(cue.text)
    lines[#lines + 1] = ""
  end

  return table.concat(lines, "\n")
end

return M
