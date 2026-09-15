-- media.output: the sidecar/buffer branch in M.deliver. media.output.sidecar
-- and media.ui are stubbed via package.loaded for the duration of this spec
-- so the branch itself is what gets tested, not their own behaviour (each has
-- its own spec: sidecar_spec.lua, ui_spec.lua). Both are restored afterwards.
---@diagnostic disable: need-check-nil, missing-fields

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

  -- ── any other mode goes through the buffer/ui route ─────────────────────
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

  package.loaded["media.output.sidecar"] = real_sidecar
  package.loaded["media.ui"] = real_ui
end
