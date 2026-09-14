---@module 'media.config.DEFAULTS'
---@brief Plugin-side defaults, and the reasoning behind each number.
---@description
--- The two axes these were chosen along: **a hover must not stutter** — every
--- default here is a number a consumer can afford while a cursor rests on a
--- path — and **nothing is configured to be useful**. Installing the plugin
--- and having `:Media probe` answer is the intended first experience.

---@type Media.Config
return {
  --- Explicit paths to the two binaries. Set either one when it is installed
  --- but not on PATH — the Windows case this exists for, where a winget or
  --- scoop install lands in a shims directory that a terminal session started
  --- before the install does not have. `core.bin` probes those locations by
  --- itself; this is the escape hatch for everything it does not guess.
  bin = {
    ffmpeg = nil,
    ffprobe = nil,
    --- The audio player behind `media.audio` — see its module header for why
    --- an audio player rather than a decoder is what drives sound. `nil` means
    --- "not on PATH", and `media.audio.available()` says so; nothing that
    --- shows a video fails over it, playback is just silent.
    mpv = nil,
    --- whisper.cpp's CLI binary, behind `media.transcribe`. `nil` means "not
    --- on PATH"; `:checkhealth media` says so, and nothing that shows a video
    --- or a picture fails over it — transcription is the one feature that
    --- needs it.
    ["whisper-cli"] = nil,
  },

  --- Hard ceiling on any one `ffmpeg`/`ffprobe` run, in milliseconds.
  ---
  --- It exists because of a specific failure, not as a formality: `ffmpeg`
  --- reading a file over a stalled network mount, or a truncated download with
  --- no moov atom, does not fail — it waits. Without a timeout that becomes a
  --- process this plugin started and nobody will ever reap. Fifteen seconds is
  --- well past the slowest legitimate seek measured here (a 4 GB h265 file,
  --- keyframe seek near the end, 2.1 s) and well short of "the editor is
  --- broken".
  ---@type integer
  timeout_ms = 15000,

  --- The poster frame.
  frame = {
    --- Where in the file the still is taken from.
    ---
    --- A percentage rather than a fixed offset, and 10% rather than 0, because
    --- of what the first frame of a real video usually is: black, a fade-in, a
    --- distributor's logo, or a slate. Ten percent is past all four in
    --- anything that is not a clip, and in a clip it is still an image of the
    --- clip. A number is taken as seconds, so `at = 0` is available to anyone
    --- who actually wants frame one.
    ---@type number|string
    at = "10%",

    --- Width in pixels the still is scaled to; the height follows the aspect
    --- ratio. 800 is chosen against the consumer, not the source: a hover
    --- float is at most a few hundred cells wide, and every pixel beyond what
    --- the terminal will draw is decode time and cache bytes spent on nothing.
    ---@type integer
    width = 800,
  },

  --- A run of stills at a fixed rate — what a consumer draws as moving
  --- picture. Every number here is chosen against the one thing that makes
  --- this feel broken or not: how long the reader waits before something
  --- moves.
  frames = {
    --- Where a run starts when the caller names no offset. Same shapes as
    --- `frame.at`; nil means the beginning, because unlike a poster frame a
    --- run is asked for by somebody who already knows which moment they want.
    ---@type number|string|nil
    from = nil,

    --- Stills per second of source material. Not the playback rate — a
    --- consumer may draw these at any speed — but the rate they are sampled
    --- at, which is what decides whether motion reads as motion. Twelve is
    --- the low end of that, and it halves the decode and the cache against
    --- twenty-four.
    ---@type number
    fps = 12,

    --- How many stills one run holds. At 12 fps this is two seconds — short
    --- enough that the first one arrives quickly, long enough that the next
    --- run can be decoded while it plays.
    ---@type integer
    count = 24,

    --- Pixel width before the consumer samples it down to cells. Far smaller
    --- than `frame.width`, and for the same reason that one is 800 rather
    --- than the source width: a terminal cell grid is a few hundred cells
    --- across at most, and every pixel past what gets drawn is decode time
    --- and cache bytes spent on nothing. At 24 frames a run, that difference
    --- is paid 24 times.
    ---@type integer
    width = 320,
  },

  --- The contact sheet: one picture of the whole file.
  sheet = {
    ---@type integer
    rows = 3,
    ---@type integer
    cols = 4,
    --- Width of the finished sheet, not of one tile.
    ---@type integer
    width = 1200,
    --- Gap between tiles, in pixels. Non-zero on purpose: a 4x3 grid of stills
    --- from one scene reads as a single smeared image without a border between
    --- the tiles.
    ---@type integer
    margin = 4,

    --- The sheet gets its own ceiling because it is a categorically different
    --- operation from everything else here: a poster frame is a seek, a sheet
    --- is a pass over the whole file. Two minutes covers a feature-length h264
    --- file on the keyframe-only path (see `core.sheet`); the interactive
    --- `timeout_ms` would kill every one of them.
    ---@type integer
    timeout_ms = 120000,
  },

  --- The waveform / spectrogram picture — visual shorthand for an audio
  --- file (or a video's soundtrack) the way a poster frame is for the
  --- picture. One ffmpeg pass over the whole file, same shape as `sheet`.
  waveform = {
    --- Width of the finished picture, in pixels.
    ---@type integer
    width = 1200,
    ---@type integer
    height = 300,

    --- `showwavespic`'s own `colors` argument — ignored by the spectrogram,
    --- which has no equivalent knob here. Left unset, ffmpeg defaults to
    --- white, which draws invisibly against a light terminal background, so
    --- a colour is always passed rather than inherited from ffmpeg.
    ---@type string
    colors = "#9cdcfe",

    --- Same reasoning as `sheet.timeout_ms`: both filters read the whole
    --- file once rather than seek, so this gets its own, longer ceiling
    --- instead of sharing the interactive `timeout_ms`.
    ---@type integer
    timeout_ms = 120000,
  },

  --- Turning speech into text — the transcription half of this plugin
  --- (ROADMAP.md's "Transcription" section). Phase 0: one engine
  --- (`whisper_cpp`), buffer and sidecar output; the fallback chain, more
  --- engines and SRT/VTT export are later phases.
  transcribe = {
    --- Which registered engine `media.transcribe` tries first.
    ---@type string
    engine = "whisper_cpp",

    --- Tried in order after `engine`, when it reports itself unavailable.
    --- Empty for now: phase 0 ships exactly one engine, so there is nothing
    --- yet to fall back to — this is where `faster_whisper`/`openai_api`
    --- join in a later phase.
    ---@type string[]
    fallback = {},

    --- Forced language (an ISO 639-1 code, e.g. `"en"`), or `nil` to let the
    --- engine detect it.
    ---@type string|nil
    lang = nil,

    --- `"transcribe"` keeps the source language; `"translate"` asks the
    --- engine for English, the only target language an engine like
    --- whisper.cpp can produce directly. Every other target language goes
    --- through language.nvim afterwards — see ROADMAP.md's "Transcription"
    --- section for why that split is not a preference but where the
    --- capability actually lives.
    ---@type "transcribe"|"translate"
    task = "transcribe",

    --- Where a finished transcript goes when the caller does not say.
    ---@type "buffer"|"sidecar"
    output = "buffer",

    --- Cross-session cache, keyed like every other entry here by the source
    --- file's mtime plus whatever engine/language/task produced it.
    ---@type boolean
    cache = true,

    --- Ceiling on the transcription call itself. `0` disables it —
    --- deliberately the default: an hour of audio is minutes of work, and
    --- the 15 s interactive `timeout_ms` above would kill every real run.
    ---@type integer
    timeout_ms = 0,

    --- Same reasoning as `sheet.timeout_ms`, for the WAV extraction step
    --- that comes before the engine runs: a full read of the file, not a
    --- seek, so it gets its own, longer ceiling.
    ---@type integer
    normalize_timeout_ms = 120000,

    whisper_cpp = {
      --- Absolute path to a GGML model file (e.g. `ggml-base.en.bin`). `nil`
      --- means "not configured" — `:checkhealth media` reports it rather
      --- than this plugin ever guessing at, or downloading, a model; see
      --- ROADMAP.md's "Risks and known traps".
      ---@type string|nil
      model = nil,
    },
  },

  --- Where rendered stills live.
  ---
  --- On disk and outliving the session, for the same reason `images.nvim`
  --- caches PDF pages that way: the expensive part is a process start plus a
  --- decode, not the draw, and the cache key carries the source file's mtime,
  --- so a kept file is safe to serve forever and an edited file misses.
  cache = {
    ---@type boolean
    enabled = true,
    --- `nil` means `stdpath("cache")/media.nvim`.
    ---@type string|nil
    dir = nil,
  },

  --- What `media.play` launches. `nil` hands the file to the system's default
  --- handler, which is the right default because it is the choice the user
  --- already made once, in their desktop environment. A string or argv list
  --- (`"mpv"`, `{ "mpv", "--loop" }`) overrides that.
  ---@type string|string[]|nil
  player = nil,

  --- The windowed mpv player behind `media.play_window` — the one a consumer
  --- opens on a video and closes again by its handle (`hover.nvim` uses it for
  --- the `<CR>` in a video hover). Always mpv, unlike `player`: a caller that
  --- wants a controllable window needs the same binary every time, and mpv is
  --- the one that gives a window, sound and its own transport keys for free.
  window = {
    --- mpv's `--autofit-larger`: the window shrinks to fit inside this fraction
    --- of the screen and never grows a small video past its own pixels, where
    --- scaling would only add blur. `""` leaves the size to mpv/the platform.
    ---@type string
    autofit = "80%x80%",

    --- Keep the window above the terminal whatever has focus. On by default
    --- because the caller that opens this generally cannot bring it to the
    --- front — inside a terminal, Windows only lets the terminal host
    --- foreground a window — and a player you cannot see is not a player. The
    --- window is short-lived anyway when a consumer ties it to a hover.
    ---@type boolean
    ontop = true,

    --- Extra mpv arguments, appended verbatim just before the file. `--loop`,
    --- `--speed=1.5`, a `--profile`, an `--sub-file` — anything mpv takes.
    ---@type string[]
    args = {},
  },

  --- `<leader>M` because a survey of this configuration found the whole
  --- capital-M leader space unused, and because these four actions want to sit
  --- together under one which-key group rather than compete for single letters.
  keymaps = {
    ---@type boolean `false` binds nothing at all
    preset = true,
    ---@type string|string[]|false|nil
    probe = "<leader>Mp",
    ---@type string|string[]|false|nil
    frame = "<leader>Mf",
    ---@type string|string[]|false|nil
    sheet = "<leader>Ms",
    ---@type string|string[]|false|nil
    play = "<leader>Mo",
    ---@type table|boolean|nil
    which_key = true,
  },
}
