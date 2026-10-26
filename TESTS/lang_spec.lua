-- media.core.lang: every spelling a person types reaches the engine as one code.

---@param H table
return function(H)
  local lang = require("media.core.lang")

  local function code(input)
    local c, err = lang.normalize(input)
    H.eq(err, nil, "no error for " .. tostring(input))
    return c
  end

  -- ── codes pass through, case-insensitively ───────────────────────────
  H.eq(code("de"), "de", "a code is itself")
  H.eq(code("DE"), "de", "case does not matter")
  H.eq(code(" en "), "en", "surrounding space does not matter")
  H.eq(code("yue"), "yue", "Whisper's three-letter codes are codes too")

  -- ── region and script tags are dropped ───────────────────────────────
  H.eq(code("de-AT"), "de", "a region tag reduces to the language")
  H.eq(code("pt_BR"), "pt", "with an underscore too")
  H.eq(code("zh-Hans"), "zh", "a script tag likewise")

  -- ── names: English, Whisper's aliases, German and native ─────────────
  H.eq(code("german"), "de", "the English name")
  H.eq(code("German"), "de", "capitalised, as whisper's own CLI spells it")
  H.eq(code("deutsch"), "de", "the German name")
  H.eq(code("Deutsch"), "de", "")
  H.eq(code("französisch"), "fr", "a German name with an umlaut")
  H.eq(code("franzoesisch"), "fr", "and its ASCII spelling")
  H.eq(code("español"), "es", "a native name")
  H.eq(code("FRANÇAIS"), "fr", "uppercase non-ASCII letters are lowercased too")
  H.eq(code("mandarin"), "zh", "one of Whisper's own aliases")
  H.eq(code("haitian creole"), "ht", "an English name with a space")

  -- ── "detect" in all its spellings is nil, not an error ───────────────
  H.eq(code(nil), nil, "nil means detect")
  H.eq(code(""), nil, "so does an empty string")
  H.eq(code("auto"), nil, "and the explicit spelling, which can override a configured language")
  H.eq(code("Detect"), nil, "")

  -- ── anything else fails loudly ───────────────────────────────────────
  local none, err = lang.normalize("klingon")
  H.eq(none, nil, "an unknown word yields no code")
  H.match(err, "unknown language", "and an error saying so")
  H.match(err, "klingon", "that names what was given")
  local _, region_err = lang.normalize("xx-YY")
  H.ok(region_err, "a region tag on an unknown language is not silently accepted")
  local _, type_err = lang.normalize(42)
  H.match(type_err, "must be a string", "a non-string is rejected, not coerced")

  -- ── codes(): the list completion and health draw from ────────────────
  local codes = lang.codes()
  H.ok(#codes >= 99, "every Whisper language is listed")
  H.ok(H.index_of(codes, "de"), "")
  H.eq(codes[1] < codes[2], true, "sorted")
end
