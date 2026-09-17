-- media.hub.text: one verb, four kinds, and the reason each cannot run.
--
-- Every sibling plugin is stubbed through `package.loaded`, so this asserts
-- the *routing* — that an image reaches images.ocr.run and a PDF reaches
-- pdfport.extract, unchanged — rather than either tool's own behaviour. It
-- therefore runs identically on a machine with all of them installed and one
-- with none, which is the point: the branch that matters most here is the one
-- taken when something is missing.
---@diagnostic disable: need-check-nil, missing-fields, param-type-mismatch

---@param H table
return function(H)
  local text = require("media.hub.text")

  local saved = {
    ocr = package.loaded["images.ocr"],
    pdfport = package.loaded["pdfport"],
    media = package.loaded["media"],
    ui = package.loaded["media.ui"],
  }

  -- Assigned one by one rather than looped over a table of pairs: a table
  -- constructor drops a key whose value is `nil`, so a module that had not been
  -- loaded when this spec started would never be un-stubbed — and every later
  -- spec would see the stub instead of the real `media`.
  ---@return nil
  local function restore()
    package.loaded["images.ocr"] = saved.ocr
    package.loaded["pdfport"] = saved.pdfport
    package.loaded["media"] = saved.media
    package.loaded["media.ui"] = saved.ui
  end

  local ok, err = pcall(function()
    -- ── a missing tool is reported with its fix, not hidden ──────────────
    package.loaded["images.ocr"] = false
    local tool = text.tool("image")
    H.eq(tool.ok, false, "no images.nvim means no OCR")
    H.match(tool.reason, "images.nvim", "the reason names what is missing")
    H.match(tool.fix, "owns OCR", "and the fix says why that plugin is the answer")
    H.falsy(
      tool.fix:find("images.nvim", 1, true),
      "without naming it a second time — the two are printed as one sentence"
    )

    -- The second, finer failure: images.nvim is there, tesseract is not.
    package.loaded["images.ocr"] = {
      run = function() end,
      bin = function()
        return nil
      end,
    }
    tool = text.tool("image")
    H.eq(tool.ok, false, "")
    H.match(tool.reason, "tesseract", "a present images.nvim without tesseract is a DIFFERENT no")
    H.match(tool.fix, "ocr.bin", "with a different fix")

    package.loaded["images.ocr"] = {
      run = function() end,
      bin = function()
        return "/usr/bin/tesseract"
      end,
    }
    H.eq(text.tool("image").ok, true, "both present is a yes")

    package.loaded["pdfport"] = false
    tool = text.tool("pdf")
    H.eq(tool.ok, false, "")
    H.match(tool.reason, "pdfport.nvim", "")

    package.loaded["pdfport"] = { extract = function() end }
    H.eq(
      text.tool("pdf").ok,
      true,
      "pdfport being installed is as far as this checks — which backend can read a given document is pdfport's own question, answered in its own words when the run happens"
    )

    tool = text.tool("other")
    H.eq(tool.ok, false, "a kind with no text operation says so")
    H.eq(tool.fix, nil, "and offers no fix, because there is none")

    -- ── which out= modes a kind can deliver to ───────────────────────────
    -- Subtitles need timestamps: `srt` is a real answer for a video and a
    -- meaningless one for a screenshot.
    H.eq_list(text.modes("image"), { "buffer", "sidecar" }, "an image has no segments to cue")
    H.eq_list(text.modes("pdf"), { "buffer", "sidecar" }, "")
    H.eq_list(
      text.modes("video"),
      { "buffer", "sidecar", "srt", "vtt" },
      "video gets every mode media.output delivers"
    )
    H.eq_list(text.modes("audio"), { "buffer", "sidecar", "srt", "vtt" }, "")

    -- ── routing: an image reaches images.ocr.run ─────────────────────────
    local ocr_calls = {}
    package.loaded["images.ocr"] = {
      bin = function()
        return "/usr/bin/tesseract"
      end,
      run = function(p, o, cb)
        ocr_calls[#ocr_calls + 1] = { path = p, opts = o }
        cb("recognised words", nil)
      end,
    }

    local got
    local handle = text.run("/a/error.png", nil, function(result, rerr)
      got = { result, rerr }
    end)
    H.eq(#ocr_calls, 1, "an image goes to images.ocr.run")
    H.eq(ocr_calls[1].path, "/a/error.png", "with the path unchanged")
    H.eq(got[1].kind, "image", "and comes back tagged with its kind")
    H.eq(got[1].text, "recognised words", "")
    H.eq(got[1].tool, "tesseract", "named by what did the work")
    H.eq(
      got[1].transcript,
      nil,
      "an image has no transcript — there are no timestamps in a still"
    )
    H.eq(handle, nil, "and nothing to cancel: OCR offers no handle, so none is invented")

    package.loaded["images.ocr"].run = function(_, _, cb)
      cb(nil, "tesseract exited with 1")
    end
    got = nil
    text.run("/a/error.png", nil, function(result, rerr)
      got = { result, rerr }
    end)
    H.eq(got[1], nil, "a failure comes back as one")
    H.eq(got[2], "tesseract exited with 1", "with the tool's own message, not a replacement")

    -- ── routing: a PDF reaches pdfport.extract ───────────────────────────
    local pdf_calls = {}
    package.loaded["pdfport"] = {
      extract = function(o)
        pdf_calls[#pdf_calls + 1] = o
        o.__callback({
          status = "ok",
          text = "page one",
          backend = "pdftotext",
          pages_processed = 24,
        })
      end,
    }

    got = nil
    text.run("/a/spec.pdf", nil, function(result, rerr)
      got = { result, rerr }
    end)
    H.eq(#pdf_calls, 1, "a PDF goes to pdfport.extract")
    H.eq(pdf_calls[1].path, "/a/spec.pdf", "")
    H.eq(type(pdf_calls[1].__callback), "function", "through the callback name pdfport asserts on")
    H.eq(got[1].kind, "pdf", "")
    H.eq(got[1].text, "page one", "")
    H.eq(got[1].tool, "pdftotext", "named by the backend that actually read it, not by `pdfport`")
    H.eq(got[1].detail, "24 pages", "the page count rides along, for a row and a sidecar header")

    -- A partial read is a result. A document whose last pages could not be
    -- read still answers most of what was asked, and discarding it would be
    -- the same mistake as refusing a run of frames because the file ended.
    package.loaded["pdfport"].extract = function(o)
      o.__callback({ status = "partial", text = "most of it", backend = "pdftotext" })
    end
    got = nil
    text.run("/a/spec.pdf", nil, function(result)
      got = result
    end)
    H.eq(got and got.text, "most of it", "a partial extraction is delivered, not thrown away")

    package.loaded["pdfport"].extract = function(o)
      o.__callback({ status = "error", error = "no available backend" })
    end
    got = nil
    text.run("/a/spec.pdf", nil, function(_, rerr)
      got = rerr
    end)
    H.eq(
      got,
      "no available backend",
      "pdfport's own wording reaches the reader — it knows why better than this module could guess"
    )

    -- `extract` asserts rather than returning an error, so a bad shape would
    -- otherwise surface as a raw Lua error out of a command.
    package.loaded["pdfport"].extract = function()
      error("pdfport.extract: opts.path must be a string")
    end
    got = nil
    text.run("/a/spec.pdf", nil, function(_, rerr)
      got = rerr
    end)
    H.match(got, "opts.path", "a raised assertion becomes an error string, not a crash")

    -- ── routing: audio and video reach the dispatcher ────────────────────
    local transcribe_calls = {}
    package.loaded["media"] = {
      transcribe_available = function()
        return true
      end,
      transcribe = function(p, o, cb)
        transcribe_calls[#transcribe_calls + 1] = { path = p, opts = o }
        cb({
          engine = "whisper_cpp",
          segments = { { s = 0, e = 1, text = "hi" } },
          text = "hi",
        }, nil)
        return { cancel = function() end }
      end,
    }

    got = nil
    handle = text.run("/a/talk.mp4", { lang = "de" }, function(result)
      got = result
    end)
    H.eq(#transcribe_calls, 1, "a video goes to media.transcribe")
    H.eq(transcribe_calls[1].opts.lang, "de", "with the caller's opts forwarded")
    H.eq(got.kind, "video", "")
    H.eq(got.text, "hi", "")
    H.ok(got.transcript ~= nil, "and the TRANSCRIPT survives — srt/vtt need the segments")
    H.eq(got.transcript.segments[1].text, "hi", "")
    H.ok(handle ~= nil, "this one does hand back a cancel handle")

    package.loaded["media"].transcribe_available = function()
      return false
    end
    got = nil
    text.run("/a/talk.mp4", nil, function(_, rerr)
      got = rerr
    end)
    H.match(got, "no transcription engine", "an unavailable engine is reported before any run")

    -- ── the fourth branch ────────────────────────────────────────────────
    got = nil
    text.run("/a/init.lua", nil, function(result, rerr)
      got = { result, rerr }
    end)
    vim.wait(200, function()
      return got ~= nil
    end, 5)
    H.eq(got[1], nil, "a kind nothing here handles produces no result")
    H.match(got[2], "into text", "and says so rather than guessing at a tool")

    -- ── where each mode writes ───────────────────────────────────────────
    H.eq(
      text.written_path("/a/error.png", "image", "sidecar"),
      "/a/error.png.ocr.md",
      "an image sidecar is the ecosystem's .ocr.md"
    )
    H.eq(text.written_path("/a/spec.pdf", "pdf", "sidecar"), "/a/spec.pdf.text.md", "")
    H.eq(
      text.written_path("/a/talk.mp4", "video", "srt"),
      "/a/talk.mp4.srt",
      "audio and video go through media.output, which already knows this"
    )
    H.eq(text.written_path("/a/error.png", "image", "buffer"), nil, "a buffer writes no file")

    -- ── delivery ─────────────────────────────────────────────────────────
    local shown = {}
    package.loaded["media.ui"] = {
      show_text = function(t, title)
        shown[#shown + 1] = { text = t, title = title }
      end,
    }

    local delivered, derr =
      text.deliver("/a/error.png", { kind = "image", text = "words", tool = "tesseract" }, "buffer")
    H.eq(delivered, true, "")
    H.eq(derr, nil, "")
    H.eq(#shown, 1, "the buffer route shows the text")
    H.eq(shown[1].text, "words", "")

    delivered, derr =
      text.deliver("/a/error.png", { kind = "image", text = "words", tool = "tesseract" }, "srt")
    H.eq(delivered, false, "an image cannot be delivered as subtitles")
    H.match(derr, "buffer, sidecar", "and the message names the modes that would have worked")
    H.falsy(derr:find("as a image"), "without an article in front of a kind name")

    -- The sidecar, against a real file, because its content is the point.
    local tmp = vim.fn.tempname() .. ".png"
    delivered, derr = text.deliver(tmp, {
      kind = "image",
      text = "recognised words",
      tool = "tesseract",
    }, "sidecar")
    H.eq(delivered, true, derr or "")
    local written = table.concat(vim.fn.readfile(tmp .. ".ocr.md"), "\n")
    H.match(written, "# OCR —", "the sidecar says what it is")
    H.match(written, "tesseract", "and what made it")
    H.match(
      written,
      "Recognition errors are possible",
      "with the same honesty the transcript one has"
    )
    H.match(written, "recognised words", "and the text itself")
    os.remove(tmp .. ".ocr.md")

    local tmp_pdf = vim.fn.tempname() .. ".pdf"
    text.deliver(tmp_pdf, {
      kind = "pdf",
      text = "page one",
      tool = "pdftotext",
      detail = "24 pages",
    }, "sidecar")
    written = table.concat(vim.fn.readfile(tmp_pdf .. ".text.md"), "\n")
    H.match(written, "# Text —", "a PDF sidecar is titled differently")
    H.match(written, "24 pages", "and carries what the backend said about the run")
    H.falsy(
      written:find("Recognition errors"),
      "with its own caveat — an unreadable page and a misread word are not the same warning"
    )
    os.remove(tmp_pdf .. ".text.md")

    -- A transcript is handed to media.output untouched, so the serialisers
    -- still see its segments.
    local delivered_srt = vim.fn.tempname() .. ".mp4"
    local ok_srt = text.deliver(delivered_srt, {
      kind = "video",
      text = "hi",
      tool = "whisper_cpp",
      transcript = { engine = "fake", segments = { { s = 0, e = 1, text = "hi" } }, text = "hi" },
    }, "srt")
    H.eq(ok_srt, true, "")
    local srt_doc = table.concat(vim.fn.readfile(delivered_srt .. ".srt"), "\n")
    H.match(
      srt_doc,
      "00:00:00,000 %-%-> 00:00:01,000",
      "the segments reached the serialiser intact"
    )
    os.remove(delivered_srt .. ".srt")
  end)

  restore()
  H.ok(ok, "hub_text_spec: " .. tostring(err))
end
