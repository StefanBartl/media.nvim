---@module 'media.core.segments'
---@brief The timestamped transcript model, shared by every engine.
---@description
--- One shape every engine's raw output is translated into
--- (`Media.Segment`/`Media.Transcript` in `@types/init.lua`), so the
--- dispatcher, the output writers, the SRT/VTT serialisers and — later — a
--- dashboard row all read one thing rather than reimplementing it per engine.

local M = {}

--- The shortest a repaired cue is allowed to be on screen, in seconds.
---
--- Only ever used for a segment whose own timestamps say it lasts no time at
--- all (see `M.cues`). Half a second is about the floor at which a reader
--- registers that a line appeared; shorter reads as a flicker, and longer
--- starts pushing into the next line's slot on dense speech.
local MIN_CUE_SECONDS = 0.5

--- The flat text view of a transcript: every segment's text, in order,
--- joined with a single space. What a buffer or a sidecar shows — the
--- segments themselves are what the SRT/VTT export reads instead.
---@param segments Media.Segment[]
---@return string
function M.to_text(segments)
  local parts = {}
  for i, segment in ipairs(segments) do
    parts[i] = segment.text
  end
  return table.concat(parts, " ")
end

---@internal
--- One segment's text, made safe to put inside a cue.
---
--- **A blank line ends a cue in both formats.** Text carrying `"\n\n"` would
--- therefore split silently into one cue plus a run of lines the parser tries
--- to read as a new timing block — and what a player then shows is not a
--- truncated line but a shifted file from that point on. Runs of blank lines
--- collapse to the single break the speaker's pause actually meant.
---
--- CRLF is normalised first so a transcript that reached disk through a
--- Windows tool behaves exactly like one that did not; outer whitespace goes
--- because a cue that starts with a newline renders as an empty first row.
---@param text string|nil
---@return string
local function clean(text)
  local s = tostring(text or "")
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("\n[ \t]*\n[ \t\n]*", "\n")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

--- The segments a subtitle file can actually carry, in order.
---
--- One place for the decisions both serialisers have to make identically,
--- because a transcript that comes out as one thing in SRT and another in VTT
--- is a defect nobody finds until a player and a text editor disagree.
---
--- **A segment with no text is dropped.** There is nothing to display, and an
--- empty cue reads as a flicker between two real ones. This is also why the
--- SubRip index counts *emitted* cues rather than segment positions: a dropped
--- segment must not leave a hole in the numbering.
---
--- **A segment with `e <= s` keeps its text.** The text is what the run spent
--- minutes producing; the timestamps are metadata an engine occasionally gets
--- wrong at a boundary. Dropping the segment throws the payload away to punish
--- the label, so the end is stretched to `MIN_CUE_SECONDS` instead — bounded
--- by where the next segment starts, so repairing a broken timestamp cannot
--- invent an overlap the source did not have. When even that leaves nothing
--- (two segments beginning at the same moment), the minimum wins: a cue nobody
--- can read is worse than a half-second overlap nobody notices.
---@param segments Media.Segment[]|nil
---@return Media.Segment[]
function M.cues(segments)
  local out = {}
  for i, segment in ipairs(segments or {}) do
    local text = clean(segment.text)
    if text ~= "" then
      local start = math.max(0, tonumber(segment.s) or 0)
      local stop = tonumber(segment.e) or start
      if stop <= start then
        local next_segment = segments[i + 1]
        local next_start = next_segment and tonumber(next_segment.s) or math.huge
        stop = math.min(start + MIN_CUE_SECONDS, math.max(next_start, start))
        if stop <= start then stop = start + MIN_CUE_SECONDS end
      end
      out[#out + 1] = { s = start, e = stop, text = text }
    end
  end
  return out
end

return M
