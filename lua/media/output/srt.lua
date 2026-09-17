---@module 'media.output.srt'
---@brief SubRip (`.srt`) — the subtitle format every player reads.
---@description
--- Phase 1 of ROADMAP.md's "Transcription": the data model
--- (`Media.Segment`/`Media.Transcript`) was always the point of making
--- timestamps mandatory on every engine, and this is what they were mandatory
--- *for*. Nothing here asks an engine for anything new.
---
--- **SubRip is not markup.** There is no escaping step, unlike its WebVTT
--- sibling: a cue's text is written out byte for byte, because a parser
--- anchors on the structure around it — a blank line, then an index, then a
--- timing line — and never reads the text as anything but text. The one thing
--- that *does* have to be handled is a blank line inside a cue, and that is
--- `media.core.segments.cues`' job, shared with WebVTT so the two formats
--- cannot disagree about what a transcript says.

local M = {}

local SUFFIX = ".srt"

--- Where this writes for `path`.
---
--- Appended to the *full* file name, the convention `media.output.sidecar`
--- argues for at length: `talk.mp4.srt` cannot collide with `talk.mov`'s
--- subtitles the way `talk.srt` would, and mpv and VLC both autoload a
--- sidecar whose name begins with the video's own, so nothing is given up for
--- it.
---@param path string
---@return string
function M.path(path)
  return path .. SUFFIX
end

--- `HH:MM:SS,mmm` — SubRip's timestamp, and the comma is not a typo.
---
--- **This is the one difference between the two formats that actually
--- bites.** SubRip separates the milliseconds with a comma, WebVTT with a full
--- stop, and every other character of the line is identical — so a file
--- written with the wrong one looks perfectly correct in a text editor and
--- loads as zero cues in a player. The two serialisers therefore each keep
--- their own formatter rather than sharing one that takes the separator as an
--- argument: an argument is precisely the thing that gets passed wrong.
---
--- Rounded rather than truncated. A boundary at 1.9995 s belongs at 2.000, and
--- truncating moves every cue in the file a millisecond early.
---@param seconds number|nil
---@return string
function M.timestamp(seconds)
  local ms = math.floor(math.max(0, tonumber(seconds) or 0) * 1000 + 0.5)
  return ("%02d:%02d:%02d,%03d"):format(
    math.floor(ms / 3600000),
    math.floor(ms % 3600000 / 60000),
    math.floor(ms % 60000 / 1000),
    ms % 1000
  )
end

--- One transcript as a SubRip document.
---
--- Pure, and public, for the reason every `args` function in this plugin is:
--- the interesting decisions are all in the exact bytes, and asserting them
--- should not need a transcription run, a file on disk, or a player.
---
--- The index is 1-based and counts the cues that are *emitted* — segments
--- `media.core.segments.cues` dropped leave no hole, because a gap in the
--- numbering is one of the few things a strict parser rejects outright.
---@param transcript Media.Transcript
---@return string
function M.serialize(transcript)
  local cues = require("media.core.segments").cues(transcript and transcript.segments or {})

  local lines = {}
  for i, cue in ipairs(cues) do
    lines[#lines + 1] = tostring(i)
    lines[#lines + 1] = ("%s --> %s"):format(M.timestamp(cue.s), M.timestamp(cue.e))
    lines[#lines + 1] = cue.text
    -- The blank line that ends the cue. Present after the last one too: a
    -- trailing newline is what makes the file a well-formed text file, and
    -- parsers that need a terminator get one.
    lines[#lines + 1] = ""
  end

  return table.concat(lines, "\n")
end

return M
