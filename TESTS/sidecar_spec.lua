-- The `.transcript.md` sidecar: path convention and document shape.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local sidecar = require("media.output.sidecar")

  H.eq(
    sidecar.path("/videos/talk.mp4"),
    "/videos/talk.mp4.transcript.md",
    "the suffix is appended to the full name, not swapped for the extension"
  )
  H.ok(
    sidecar.path("/videos/talk.mp4") ~= sidecar.path("/videos/talk.mov"),
    "two source extensions do not collide on one sidecar"
  )

  ---@type Media.Transcript
  local transcript = {
    engine = "whisper_cpp",
    model = "ggml-base.en.bin",
    lang = "en",
    duration = nil,
    segments = {
      { s = 0, e = 1, text = "Hello" },
      { s = 1, e = 2, text = "world." },
    },
    text = "Hello world.",
  }

  local content = sidecar.content("/videos/talk.mp4", transcript)
  H.match(content, "^# Transcript %— talk%.mp4", "the heading names the source file")
  H.match(content, "whisper_cpp %(ggml%-base%.en%.bin%)", "engine and model are both recorded")
  H.match(content, "Hello world%.", "the flat text is in the body")
end
