-- media.output.srt: the SubRip document, byte for byte. Pure — no ffmpeg, no
-- engine, no disk, which is the whole reason `serialize` and `timestamp` are
-- public. The edge cases in the fixture below are the ones a real whisper.cpp
-- run produces and a hand-written test never would.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local srt = require("media.output.srt")

  -- ── the timestamp, and its comma ────────────────────────────────────────
  H.eq(srt.timestamp(0), "00:00:00,000", "zero is fully padded, not '0:0:0'")
  H.eq(srt.timestamp(1.5), "00:00:01,500", "SubRip separates milliseconds with a COMMA")
  H.eq(srt.timestamp(61.25), "00:01:01,250", "minutes carry")
  H.eq(srt.timestamp(3661.001), "01:01:01,001", "hours carry, and a single millisecond survives")
  H.eq(
    srt.timestamp(359999.999),
    "99:59:59,999",
    "the hours field is not capped at two digits' worth of a day"
  )

  H.eq(srt.timestamp(1.9995), "00:00:02,000", "milliseconds round rather than truncate")
  H.eq(
    srt.timestamp(-5),
    "00:00:00,000",
    "a negative offset clamps to zero instead of formatting as one"
  )
  H.eq(srt.timestamp(nil), "00:00:00,000", "a missing offset is zero, not an error")

  -- ── the document ────────────────────────────────────────────────────────
  ---@type Media.Transcript
  local transcript = {
    engine = "fake",
    segments = {
      { s = 0, e = 1.5, text = "Hello." },
      { s = 1.5, e = 3, text = "World." },
    },
    text = "Hello. World.",
  }

  local doc = srt.serialize(transcript)
  H.eq(
    doc,
    table.concat({
      "1",
      "00:00:00,000 --> 00:00:01,500",
      "Hello.",
      "",
      "2",
      "00:00:01,500 --> 00:00:03,000",
      "World.",
      "",
    }, "\n"),
    "two segments render as two numbered cues, each closed by a blank line"
  )

  H.eq(
    srt.serialize({ engine = "fake", segments = {}, text = "" }),
    "",
    "no segments is an empty document, not a malformed one"
  )

  H.falsy(
    srt.serialize(transcript):find("WEBVTT", 1, true),
    "SubRip has no header — that is WebVTT's"
  )

  -- ── empty segments are dropped, and the numbering stays contiguous ──────
  local with_gaps = srt.serialize({
    engine = "fake",
    segments = {
      { s = 0, e = 1, text = "one" },
      { s = 1, e = 2, text = "   " },
      { s = 2, e = 3, text = "" },
      { s = 3, e = 4, text = "two" },
    },
    text = "one two",
  })
  H.match(with_gaps, "^1\n", "the first surviving cue is numbered 1")
  H.match(
    with_gaps,
    "\n2\n00:00:03,000",
    "the cue after two dropped ones is 2, not 4 — a gap is what a strict parser rejects"
  )
  H.falsy(
    with_gaps:find("00:00:01,000 %-%-> 00:00:02,000"),
    "a whitespace-only segment produced no cue at all"
  )

  -- ── a zero-length segment keeps its text ────────────────────────────────
  local repaired = srt.serialize({
    engine = "fake",
    segments = { { s = 10, e = 10, text = "still said it" } },
    text = "still said it",
  })
  H.match(repaired, "still said it", "text is never thrown away because its timestamps are broken")
  H.match(
    repaired,
    "00:00:10,000 %-%-> 00:00:10,500",
    "a zero-length cue is stretched to the minimum visible duration"
  )

  local bounded = srt.serialize({
    engine = "fake",
    segments = {
      { s = 10, e = 9, text = "inverted" },
      { s = 10.2, e = 11, text = "next" },
    },
    text = "inverted next",
  })
  H.match(
    bounded,
    "00:00:10,000 %-%-> 00:00:10,200",
    "the repair stops where the next segment starts, so it cannot invent an overlap"
  )

  -- ── a blank line inside a cue would end it ──────────────────────────────
  local multiline = srt.serialize({
    engine = "fake",
    segments = {
      { s = 0, e = 2, text = "first line\n\nsecond line" },
      { s = 2, e = 3, text = "after" },
    },
    text = "first line second line after",
  })
  H.match(
    multiline,
    "first line\nsecond line",
    "a blank line inside the text collapses to a single break"
  )
  H.match(multiline, "\n2\n", "so the cue after it is still cue 2 rather than unparsed junk")

  H.match(
    srt.serialize({
      engine = "fake",
      segments = { { s = 0, e = 1, text = "crlf\r\nline" } },
      text = "crlf line",
    }),
    "crlf\nline",
    "CRLF is normalised, so a transcript written by a Windows tool behaves like any other"
  )

  -- ── SubRip is not markup ────────────────────────────────────────────────
  H.match(
    srt.serialize({
      engine = "fake",
      segments = { { s = 0, e = 1, text = "a < b & c > d" } },
      text = "a < b & c > d",
    }),
    "a < b & c > d",
    "angle brackets and ampersands are written verbatim — SubRip has no markup to escape them from"
  )

  -- ── the path convention ─────────────────────────────────────────────────
  H.eq(
    srt.path("/tmp/talk.mp4"),
    "/tmp/talk.mp4.srt",
    "the suffix is appended to the full name, so talk.mp4 and talk.mov do not collide"
  )
end
