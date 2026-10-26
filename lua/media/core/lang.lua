---@module 'media.core.lang'
---@brief The spoken-language argument, normalized to the code every engine takes.
---@description
--- `lang=` arrives in whatever a person types: `de`, `DE`, `de-AT`, `german`,
--- `deutsch`, `Deutsch`. Every engine wants the same thing — an ISO 639-1 code
--- out of Whisper's own language list (whisper.cpp's `-l`, openai-whisper's
--- `--language`) — so the translation happens once, here, before the engine
--- is even resolved, instead of each engine growing its own lenient parser.
---
--- The code list is Whisper's (`whisper/tokenizer.py`, `LANGUAGES`, read from
--- the installed `openai-whisper` 20250625): every engine this plugin has or
--- plans is a Whisper derivative, so that list is exactly what they accept.
--- English names come from the same table; the German and native names are
--- this module's own, for the languages people actually type that way.
---
--- `auto`, `detect` and `none` mean "let the engine detect it" — the explicit
--- spelling of `lang = nil`, so a command can override a configured language
--- back to detection.

local M = {}

--- Whisper's language codes and their English names.
---@type table<string, string>
local CODES = {
  en = "english",
  zh = "chinese",
  de = "german",
  es = "spanish",
  ru = "russian",
  ko = "korean",
  fr = "french",
  ja = "japanese",
  pt = "portuguese",
  tr = "turkish",
  pl = "polish",
  ca = "catalan",
  nl = "dutch",
  ar = "arabic",
  sv = "swedish",
  it = "italian",
  id = "indonesian",
  hi = "hindi",
  fi = "finnish",
  vi = "vietnamese",
  he = "hebrew",
  uk = "ukrainian",
  el = "greek",
  ms = "malay",
  cs = "czech",
  ro = "romanian",
  da = "danish",
  hu = "hungarian",
  ta = "tamil",
  no = "norwegian",
  th = "thai",
  ur = "urdu",
  hr = "croatian",
  bg = "bulgarian",
  lt = "lithuanian",
  la = "latin",
  mi = "maori",
  ml = "malayalam",
  cy = "welsh",
  sk = "slovak",
  te = "telugu",
  fa = "persian",
  lv = "latvian",
  bn = "bengali",
  sr = "serbian",
  az = "azerbaijani",
  sl = "slovenian",
  kn = "kannada",
  et = "estonian",
  mk = "macedonian",
  br = "breton",
  eu = "basque",
  is = "icelandic",
  hy = "armenian",
  ne = "nepali",
  mn = "mongolian",
  bs = "bosnian",
  kk = "kazakh",
  sq = "albanian",
  sw = "swahili",
  gl = "galician",
  mr = "marathi",
  pa = "punjabi",
  si = "sinhala",
  km = "khmer",
  sn = "shona",
  yo = "yoruba",
  so = "somali",
  af = "afrikaans",
  oc = "occitan",
  ka = "georgian",
  be = "belarusian",
  tg = "tajik",
  sd = "sindhi",
  gu = "gujarati",
  am = "amharic",
  yi = "yiddish",
  lo = "lao",
  uz = "uzbek",
  fo = "faroese",
  ht = "haitian creole",
  ps = "pashto",
  tk = "turkmen",
  nn = "nynorsk",
  mt = "maltese",
  sa = "sanskrit",
  lb = "luxembourgish",
  my = "myanmar",
  bo = "tibetan",
  tl = "tagalog",
  mg = "malagasy",
  as = "assamese",
  tt = "tatar",
  haw = "hawaiian",
  ln = "lingala",
  ha = "hausa",
  ba = "bashkir",
  jw = "javanese",
  su = "sundanese",
  yue = "cantonese",
}

--- Names that are not the English one: Whisper's own aliases, then German and
--- native spellings. Lowercase, with and without umlauts/accents, because
--- `string.lower` is byte-wise and a person types either.
---@type table<string, string>
local ALIASES = {
  -- Whisper's `TO_LANGUAGE_CODE` aliases.
  burmese = "my",
  valencian = "ca",
  flemish = "nl",
  haitian = "ht",
  letzeburgesch = "lb",
  pushto = "ps",
  panjabi = "pa",
  moldavian = "ro",
  moldovan = "ro",
  sinhalese = "si",
  castilian = "es",
  mandarin = "zh",
  -- German and native names.
  deutsch = "de",
  englisch = "en",
  ["französisch"] = "fr",
  franzoesisch = "fr",
  franzosisch = "fr",
  ["français"] = "fr",
  francais = "fr",
  spanisch = "es",
  ["español"] = "es",
  espanol = "es",
  italienisch = "it",
  italiano = "it",
  portugiesisch = "pt",
  ["português"] = "pt",
  portugues = "pt",
  ["niederländisch"] = "nl",
  niederlaendisch = "nl",
  niederlandisch = "nl",
  ["holländisch"] = "nl",
  hollaendisch = "nl",
  nederlands = "nl",
  polnisch = "pl",
  polski = "pl",
  russisch = "ru",
  ukrainisch = "uk",
  tschechisch = "cs",
  ["čeština"] = "cs",
  cestina = "cs",
  slowakisch = "sk",
  ["slovenčina"] = "sk",
  slovencina = "sk",
  ungarisch = "hu",
  magyar = "hu",
  ["rumänisch"] = "ro",
  rumaenisch = "ro",
  rumanisch = "ro",
  ["română"] = "ro",
  romana = "ro",
  kroatisch = "hr",
  hrvatski = "hr",
  serbisch = "sr",
  srpski = "sr",
  slowenisch = "sl",
  ["slovenščina"] = "sl",
  slovenscina = "sl",
  bulgarisch = "bg",
  griechisch = "el",
  ["türkisch"] = "tr",
  tuerkisch = "tr",
  turkisch = "tr",
  ["türkçe"] = "tr",
  turkce = "tr",
  schwedisch = "sv",
  svenska = "sv",
  ["dänisch"] = "da",
  daenisch = "da",
  danisch = "da",
  dansk = "da",
  norwegisch = "no",
  norsk = "no",
  finnisch = "fi",
  suomi = "fi",
  japanisch = "ja",
  chinesisch = "zh",
  koreanisch = "ko",
  arabisch = "ar",
  ["hebräisch"] = "he",
  hebraeisch = "he",
  hebraisch = "he",
  katalanisch = "ca",
  ["català"] = "ca",
  catala = "ca",
}

--- Spellings that mean "detect the language".
---@type table<string, true>
local DETECT = { auto = true, detect = true, none = true }

--- The engine-facing code for `input`.
---
--- Returns `nil, nil` for "detect" (nil, `""`, `auto`, `detect`, `none`), a
--- code for anything recognised, and `nil, err` for anything else — an
--- unknown word must fail loudly rather than reach an engine that would
--- either reject it after minutes of WAV extraction or, worse, ignore it.
---
--- Pure and public, like `resolver.build_chain`: the whole content is the
--- mapping, and it should be assertable without an engine anywhere.
---@param input string|nil
---@return string|nil code
---@return string|nil err
function M.normalize(input)
  if input == nil then return nil, nil end
  if type(input) ~= "string" then
    return nil, ("media: lang must be a string, got %s"):format(type(input))
  end
  -- `vim.fn.tolower` lowercases UTF-8 (`FRANÇAIS`), `string.lower` only
  -- ASCII; the latter is the fallback for a caller in a fast event context.
  local trimmed = vim.trim(input)
  local s = vim.in_fast_event() and trimmed:lower() or vim.fn.tolower(trimmed)
  if s == "" or DETECT[s] then return nil, nil end

  if CODES[s] then return s, nil end

  -- A region or script tag after the language: `de-AT`, `de_DE`, `zh-Hans`.
  local base = s:match("^(%a%a%a?)[-_]%w+$")
  if base and CODES[base] then return base, nil end

  if ALIASES[s] then return ALIASES[s], nil end
  for code, name in pairs(CODES) do
    if name == s then return code, nil end
  end

  return nil,
    ("media: unknown language %q — use an ISO 639-1 code (de, en, fr, …), a name (german, deutsch), or auto"):format(
      input
    )
end

--- Every code Whisper knows, sorted — for completion and `:checkhealth`.
---@return string[]
function M.codes()
  local out = {}
  for code in pairs(CODES) do
    out[#out + 1] = code
  end
  table.sort(out)
  return out
end

return M
