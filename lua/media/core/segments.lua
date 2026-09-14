---@module 'media.core.segments'
---@brief The timestamped transcript model, shared by every engine.
---@description
--- One shape every engine's raw output is translated into
--- (`Media.Segment`/`Media.Transcript` in `@types/init.lua`), so the
--- dispatcher, the output writers, and — later — a dashboard row and an
--- SRT/VTT export all read one thing rather than reimplementing it per
--- engine. SRT/VTT serialisers are phase 1 (ROADMAP.md, "Transcription");
--- this currently holds only what phase 0 needs.

local M = {}

--- The flat text view of a transcript: every segment's text, in order,
--- joined with a single space. What a buffer or a sidecar shows — the
--- segments themselves are what a future SRT/VTT export reads instead.
---@param segments Media.Segment[]
---@return string
function M.to_text(segments)
  local parts = {}
  for i, segment in ipairs(segments) do
    parts[i] = segment.text
  end
  return table.concat(parts, " ")
end

return M
