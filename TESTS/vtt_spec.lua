-- media.output.vtt: the WebVTT document. Same fixture shape as srt_spec.lua
-- on purpose — the two formats differ in four places and this is where those
-- four are pinned, because everywhere else they look identical.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local vtt = require("media.output.vtt")
  local srt = require("media.output.srt")

  -- ── the timestamp, and its full stop ────────────────────────────────────
  H.eq(vtt.timestamp(0), "00:00:00.000", "zero is fully padded")
  H.eq(vtt.timestamp(1.5), "00:00:01.500", "WebVTT separates milliseconds with a FULL STOP")
  H.eq(vtt.timestamp(61.25), "00:01:01.250", "minutes carry")
  H.eq(vtt.timestamp(3661.001), "01:01:01.001", "hours carry")
  H.eq(
    vtt.timestamp(90),
    "00:01:30.000",
    "the hours field is written even below an hour — the short form is legal but not universally read"
  )
  H.eq(vtt.timestamp(1.9995), "00:00:02.000", "milliseconds round rather than truncate")
  H.eq(vtt.timestamp(-5), "00:00:00.000", "a negative offset clamps to zero")
  H.eq(vtt.timestamp(nil), "00:00:00.000", "a missing offset is zero, not an error")

  -- The classic defect this pair exists to prevent, asserted directly.
  H.falsy(vtt.timestamp(1.5):find(",", 1, true), "a WebVTT timestamp never contains a comma")
  H.falsy(
    srt.timestamp(1.5):find(".", 1, true),
    "and a SubRip timestamp never contains a full stop"
  )

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

  H.eq(
    vtt.serialize(transcript),
    table.concat({
      "WEBVTT",
      "",
      "00:00:00.000 --> 00:00:01.500",
      "Hello.",
      "",
      "00:00:01.500 --> 00:00:03.000",
      "World.",
      "",
    }, "\n"),
    "the header, a blank line, then unnumbered cues"
  )

  H.eq(
    vtt.serialize({ engine = "fake", segments = {}, text = "" }),
    "WEBVTT\n",
    "a transcript with no segments is still a valid WebVTT file — the header is what makes it one"
  )

  H.falsy(
    vtt.serialize(transcript):find("\n1\n", 1, true),
    "no cue index: WebVTT's identifier is a name for a stylesheet, not SubRip's running number"
  )

  -- ── cue text is markup, and this is the whole difference from SubRip ────
  H.eq(
    vtt.escape("a < b"),
    "a &lt; b",
    "a bare < would open a tag that swallows the rest of the cue"
  )
  H.eq(vtt.escape("a > b"), "a &gt; b", "and > is escaped with it")
  H.eq(vtt.escape("Tom & Jerry"), "Tom &amp; Jerry", "ampersands become entities")
  H.eq(
    vtt.escape("a & b < c"),
    "a &amp; b &lt; c",
    "ampersands go FIRST — the other order escapes this function's own output on the second pass"
  )
  H.eq(
    vtt.escape("value --> result"),
    "value --&gt; result",
    "escaping > also disarms -->, which WebVTT's parser would otherwise read as a timing line"
  )
  H.eq(vtt.escape(nil), "", "nil text is empty, not an error")

  local arrowed = vtt.serialize({
    engine = "fake",
    segments = { { s = 0, e = 1, text = "a --> b" }, { s = 1, e = 2, text = "after" } },
    text = "a --> b after",
  })
  H.match(arrowed, "a %-%-&gt; b", "an arrow in the transcript reaches the file escaped")
  H.eq(
    select(2, arrowed:gsub("%-%-> ", "")),
    2,
    "so the file still has exactly two timing lines, not four — an unescaped arrow shifts every cue after it"
  )

  -- ── the shared cue rules behave the same as in SubRip ───────────────────
  local with_gaps = vtt.serialize({
    engine = "fake",
    segments = {
      { s = 0, e = 1, text = "one" },
      { s = 1, e = 2, text = "  \n  " },
      { s = 2, e = 3, text = "two" },
    },
    text = "one two",
  })
  H.eq(select(2, with_gaps:gsub("%-%-> ", "")), 2, "a whitespace-only segment produces no cue")

  H.match(
    vtt.serialize({
      engine = "fake",
      segments = { { s = 0, e = 2, text = "first\n\nsecond" } },
      text = "first second",
    }),
    "first\nsecond",
    "a blank line inside a cue collapses — it would otherwise end the cue"
  )

  H.match(
    vtt.serialize({
      engine = "fake",
      segments = { { s = 10, e = 10, text = "still said it" } },
      text = "still said it",
    }),
    "00:00:10.000 %-%-> 00:00:10.500\nstill said it",
    "a zero-length cue keeps its text and is stretched to the minimum visible duration"
  )

  -- ── the path convention ─────────────────────────────────────────────────
  H.eq(vtt.path("/tmp/talk.mp4"), "/tmp/talk.mp4.vtt", "the suffix is appended to the full name")
end
