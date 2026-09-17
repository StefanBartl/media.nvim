-- media.output: the four branches in M.deliver, plus is_mode and
-- written_path. media.output.sidecar, media.output.srt and media.ui are
-- stubbed via package.loaded for the duration of this spec so the branches
-- themselves are what get tested, not their own behaviour (each has its own:
-- sidecar_spec.lua, srt_spec.lua, vtt_spec.lua, ui_spec.lua). All are
-- restored afterwards.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch

---@param H table
return function(H)
  local output = require("media.output")

  local real_sidecar = require("media.output.sidecar")
  local real_ui = require("media.ui")

  ---@type Media.Transcript
  local transcript = {
    engine = "fake",
    segments = { { s = 0, e = 1, text = "hi" } },
    text = "hi",
  }

  -- ── mode = "sidecar" delegates to media.output.sidecar.write verbatim ──
  local sidecar_calls = {}
  package.loaded["media.output.sidecar"] = {
    write = function(path, t)
      sidecar_calls[#sidecar_calls + 1] = { path = path, transcript = t }
      return true, nil
    end,
  }

  local ok1, err1 = output.deliver("/tmp/clip.mkv", transcript, "sidecar")
  H.eq(ok1, true, "the sidecar writer's own result is passed through")
  H.eq(err1, nil, "")
  H.eq(#sidecar_calls, 1, "sidecar.write was called exactly once")
  H.eq(sidecar_calls[1].path, "/tmp/clip.mkv", "with the path forwarded unchanged")
  H.eq(sidecar_calls[1].transcript, transcript, "and the transcript forwarded unchanged")

  local sidecar_fail_calls = 0
  package.loaded["media.output.sidecar"] = {
    write = function()
      sidecar_fail_calls = sidecar_fail_calls + 1
      return false, "disk full"
    end,
  }
  local ok2, err2 = output.deliver("/tmp/clip.mkv", transcript, "sidecar")
  H.eq(ok2, false, "a sidecar write failure is reported, not swallowed")
  H.eq(err2, "disk full", "with the writer's own error message")

  -- ── mode = "buffer" goes through the ui route ───────────────────────────
  local shown = {}
  package.loaded["media.ui"] = {
    show_text = function(text, title)
      shown[#shown + 1] = { text = text, title = title }
    end,
  }

  local ok3, err3 = output.deliver("/some/dir/A Talk.mkv", transcript, "buffer")
  H.eq(ok3, true, "the buffer route always reports success")
  H.eq(err3, nil, "")
  H.eq(#shown, 1, "media.ui.show_text was called exactly once")
  H.eq(shown[1].text, "hi", "the delivered text is the transcript's segments, flattened")
  H.match(shown[1].title, "A Talk.mkv", "the title carries the file name, not the whole path")

  H.eq(#sidecar_calls, 1, "the buffer route never touches the sidecar writer")

  -- ── the subtitle modes serialise and write ──────────────────────────────
  -- The serialiser is stubbed (srt_spec.lua/vtt_spec.lua own its output); what
  -- is under test here is that `deliver` asks the right module for the path,
  -- asks it for the document, and actually puts one on disk.
  local real_srt = require("media.output.srt")
  local tmp = vim.fn.tempname() .. ".srt"
  package.loaded["media.output.srt"] = {
    path = function()
      return tmp
    end,
    serialize = function(t)
      H.eq(t, transcript, "the transcript reaches the serialiser unchanged")
      return "1\n00:00:00,000 --> 00:00:01,000\nhi\n"
    end,
  }

  local ok4, err4 = output.deliver("/some/dir/A Talk.mkv", transcript, "srt")
  H.eq(ok4, true, "a written subtitle file reports success")
  H.eq(err4, nil, "")
  local written = table.concat(vim.fn.readfile(tmp), "\n")
  H.match(written, "00:00:00,000", "and the serialiser's document is what landed on disk")
  H.eq(#shown, 1, "the subtitle route never opens a buffer")
  os.remove(tmp)
  package.loaded["media.output.srt"] = real_srt

  -- ── an unknown mode is an error, not a silent buffer ────────────────────
  -- The defect this closes: `out=str` used to fall through to the buffer, so
  -- the reader waited out a whole transcription and got a scratch window with
  -- no explanation of where their subtitles went.
  local ok5, err5 = output.deliver("/some/dir/A Talk.mkv", transcript, "str")
  H.eq(ok5, false, "an unrecognised mode fails")
  H.match(err5, "unknown output mode", "and says so")
  H.match(err5, "srt", "naming the modes that would have worked")
  H.eq(#shown, 1, "without having opened a buffer on the way")

  H.eq(output.is_mode("buffer"), true, "is_mode knows every delivered mode")
  H.eq(output.is_mode("sidecar"), true, "")
  H.eq(output.is_mode("srt"), true, "")
  H.eq(output.is_mode("vtt"), true, "")
  H.eq(output.is_mode(nil), true, "nil means 'the configured default', which is always one")
  H.eq(output.is_mode(""), true, "an empty out= is the same thing as none")
  H.eq(
    output.is_mode("clipboard"),
    false,
    "a mode the roadmap plans but this does not deliver yet is rejected"
  )

  -- The real sidecar module from here on: `written_path` asks it for the
  -- suffix, and the stub above only ever had a `write`.
  package.loaded["media.output.sidecar"] = real_sidecar

  H.eq(output.written_path("/a/talk.mp4", "buffer"), nil, "a buffer writes no file")
  H.eq(output.written_path("/a/talk.mp4", nil), nil, "and neither does nothing")
  H.eq(
    output.written_path("/a/talk.mp4", "sidecar"),
    "/a/talk.mp4.transcript.md",
    "the sidecar path comes from the sidecar module, not a second copy of the suffix"
  )
  H.eq(output.written_path("/a/talk.mp4", "srt"), "/a/talk.mp4.srt", "")
  H.eq(output.written_path("/a/talk.mp4", "vtt"), "/a/talk.mp4.vtt", "")

  package.loaded["media.output.sidecar"] = real_sidecar
  package.loaded["media.ui"] = real_ui
end
