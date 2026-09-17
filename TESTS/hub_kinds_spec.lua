-- media.hub.kinds: what a path is, and what its text would be called.
--
-- Pure, and the reason it is worth its own spec: every wrong answer here is
-- silent. A `.png` classified as "other" does not error, it just quietly never
-- appears in the dashboard; a sidecar suffix that does not match what actually
-- writes the file makes every row say "missing" for text that is right there.
--
-- images.nvim is stubbed through `package.loaded` in the one case that asks
-- about it, so this runs identically on a machine that has it and one that
-- does not.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local kinds = require("media.hub.kinds")

  -- ── the four kinds, and the fifth answer ────────────────────────────────
  H.eq(kinds.of("/a/talk.mp4"), "video", "media.nvim's own answer, from media.formats")
  H.eq(kinds.of("/a/notes.m4a"), "audio", "")
  H.eq(kinds.of("/a/spec.pdf"), "pdf", "")
  H.eq(kinds.of("/a/error.png"), "image", "")
  H.eq(kinds.of("/a/init.lua"), "other", "a source file is not this plugin's business")
  H.eq(kinds.of("/a/README"), "other", "and neither is a file with no extension")
  H.eq(kinds.of(nil), "other", "nil is an answer, not an error")
  H.eq(kinds.of(""), "other", "")

  H.eq(kinds.of("/a/TALK.MP4"), "video", "a filename is case-insensitive")
  H.eq(kinds.of("/a/Spec.PDF"), "pdf", "")

  -- ── a PDF is a PDF whether or not anything can read it ──────────────────
  -- The trap this avoids: `images.integrations.picker.is_pdf` also asks
  -- whether the machine can *rasterize* it. That is right before promising to
  -- draw a page and wrong here — classifying by capability would drop the row
  -- that tells the reader what is missing.
  local real_picker = package.loaded["images.integrations.picker"]
  package.loaded["images.integrations.picker"] = {
    is_image = function()
      return false
    end,
    is_pdf = function()
      return false
    end,
  }
  H.eq(kinds.of("/a/spec.pdf"), "pdf", "a PDF nothing on this machine can open is still a PDF")
  H.eq(
    kinds.of("/a/error.png"),
    "other",
    "but images.nvim is the authority on what an image is, and it said no"
  )

  -- ── and without images.nvim, the fallback list answers ──────────────────
  package.loaded["images.integrations.picker"] = nil
  local real_images = package.loaded["images"]
  package.loaded["images"] = false
  H.eq(
    kinds.of("/a/error.png"),
    "image",
    "a machine without images.nvim still lists its PNGs — the row is how the reader learns OCR is available once it is installed"
  )
  H.eq(kinds.of("/a/scan.tiff"), "image", "")
  package.loaded["images"] = real_images
  package.loaded["images.integrations.picker"] = real_picker

  -- ── three operations, three sidecar names ──────────────────────────────
  -- Not three spellings of one thing: OCR misreads, transcription mishears,
  -- extraction is exact. The name is the only warning a reader gets.
  H.eq(
    kinds.sidecar("/a/talk.mp4"),
    "/a/talk.mp4.transcript.md",
    "video and audio use media.output.sidecar's own suffix, unchanged"
  )
  H.eq(kinds.sidecar("/a/notes.m4a"), "/a/notes.m4a.transcript.md", "")
  H.eq(
    kinds.sidecar("/a/error.png"),
    "/a/error.png.ocr.md",
    "images use casedesk.nvim's established .ocr.md"
  )
  H.eq(kinds.sidecar("/a/spec.pdf"), "/a/spec.pdf.text.md", "PDFs get the new one")
  H.eq(kinds.sidecar("/a/init.lua"), nil, "a kind with no text operation has no sidecar")

  H.eq(
    kinds.sidecar("/a/talk.mp4", "audio"),
    "/a/talk.mp4.transcript.md",
    "an already-known kind is taken rather than recomputed"
  )

  -- The suffix is appended to the FULL name, never swapped for the extension:
  -- talk.mp4 and talk.mov in one directory must not share a sidecar.
  H.falsy(
    kinds.sidecar("/a/talk.mp4") == kinds.sidecar("/a/talk.mov"),
    "two containers of the same name do not collide"
  )

  -- ── a scan must not list its own output ────────────────────────────────
  H.eq(kinds.is_sidecar("/a/talk.mp4.transcript.md"), true, "")
  H.eq(kinds.is_sidecar("error.png.ocr.md"), true, "a bare name works too — the walk passes one")
  H.eq(kinds.is_sidecar("/a/spec.pdf.text.md"), true, "")
  H.eq(kinds.is_sidecar("/a/notes.md"), false, "an ordinary markdown file is not a sidecar")
  H.eq(kinds.is_sidecar("/a/talk.mp4"), false, "")
  H.eq(kinds.is_sidecar(nil), false, "")
  H.eq(
    kinds.is_sidecar(".ocr.md"),
    false,
    "the suffix alone is a file named nothing — not a sidecar for anything"
  )

  -- ── the verb a row and an error message use ────────────────────────────
  H.eq(kinds.verb("image"), "ocr", "")
  H.eq(kinds.verb("pdf"), "text", "")
  H.eq(kinds.verb("video"), "transcript", "")
  H.eq(kinds.verb("audio"), "transcript", "")
  H.eq(kinds.verb("other"), nil, "")
end
