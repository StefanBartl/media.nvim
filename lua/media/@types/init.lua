---@module 'media.@types'
---@brief Type declarations for media.nvim.
---@description
--- Annotations only — the module returns an empty table and exists so that
--- every alias has exactly one definition. A LuaLS alias name is global to the
--- workspace, so re-declaring `Media.Probe` next to a second consumer is a
--- `duplicate-doc-alias`, not an override (`LLS-23`).

---@class Media.Config
---@field bin Media.Config.Bin
---@field timeout_ms integer
---@field frame Media.Config.Frame
---@field sheet Media.Config.Sheet
---@field waveform Media.Config.Waveform
---@field transcribe Media.Config.Transcribe
---@field cache Media.Config.Cache
---@field player string|string[]|nil
---@field window Media.Config.Window
---@field keymaps Media.Config.Keymaps

--- The windowed mpv player behind `media.play_window` — a real mpv window a
--- consumer opens on a file and stops again by its handle. Distinct from
--- `player`, which is a fire-and-forget handoff to whatever the user configured
--- (or the system default): this one is always mpv, always owned.
---@class Media.Config.Window
---@field autofit string  # mpv `--autofit-larger`, e.g. "80%x80%"; "" disables the size hint
---@field ontop boolean   # keep the window above the terminal regardless of focus
---@field args string[]   # extra mpv arguments, appended verbatim before the file

---@class Media.Config.Bin
---@field ffmpeg string|nil
---@field ffprobe string|nil
---@field mpv string|nil
---@field ["whisper-cli"] string|nil  # `media.core.bin.find("whisper-cli")` reads this key

---@class Media.Config.Frame
---@field at number|string  # seconds, or a percentage of the duration ("10%")
---@field width integer

---@class Media.Config.Sheet
---@field rows integer
---@field cols integer
---@field width integer
---@field margin integer
---@field timeout_ms integer

---@class Media.Config.Waveform
---@field width integer
---@field height integer
---@field colors string  # `showwavespic`'s own argument; ignored for a spectrogram
---@field timeout_ms integer

---@class Media.Config.Transcribe
---@field engine string
---@field fallback string[]
---@field lang string|nil
---@field task "transcribe"|"translate"
---@field output "buffer"|"sidecar"
---@field cache boolean
---@field timeout_ms integer  # 0 = no timeout
---@field normalize_timeout_ms integer
---@field whisper_cpp Media.Config.Transcribe.WhisperCpp

---@class Media.Config.Transcribe.WhisperCpp
---@field model string|nil  # absolute path to a GGML .bin model file

---@class Media.Config.Cache
---@field enabled boolean
---@field dir string|nil

---@class Media.Config.Keymaps
---@field preset boolean
---@field probe string|string[]|false|nil
---@field frame string|string[]|false|nil
---@field sheet string|string[]|false|nil
---@field play string|string[]|false|nil
---@field which_key table|boolean|nil

--- What `setup()` accepts, as opposed to what is in effect.
---
--- **Why this is not `Media.Config` with question marks.** The two are genuinely
--- different types and collapsing them costs one of the two things worth having:
--- a total `Media.Config` lets every internal read be `cfg.frame.at` without a
--- nil check, because `config.get()` guarantees the field is there; a partial
--- one is what a user actually writes, because `{ frame = { width = 640 } }` is
--- the normal way to change one number. Declared as required, the partial is
--- rejected; declared as optional, every read inside the plugin grows a guard
--- against a case `get()` has already ruled out.
---
--- The nested classes repeat their fields for the same reason — LuaLS has no
--- `Partial<T>`, and `frame?: Media.Config.Frame` would still demand every field
--- of `Media.Config.Frame` once `frame` is given at all.
---@class Media.Opts
---@field bin? Media.Opts.Bin
---@field timeout_ms? integer
---@field frame? Media.Opts.Frame
---@field sheet? Media.Opts.Sheet
---@field waveform? Media.Opts.Waveform
---@field transcribe? Media.Opts.Transcribe
---@field cache? Media.Opts.Cache
---@field player? string|string[]
---@field window? Media.Opts.Window
---@field keymaps? Media.Opts.Keymaps

---@class Media.Opts.Bin
---@field ffmpeg? string
---@field ffprobe? string
---@field mpv? string
---@field ["whisper-cli"]? string

---@class Media.Opts.Frame
---@field at? number|string
---@field width? integer

---@class Media.Opts.Sheet
---@field rows? integer
---@field cols? integer
---@field width? integer
---@field margin? integer
---@field timeout_ms? integer

---@class Media.Opts.Waveform
---@field width? integer
---@field height? integer
---@field colors? string
---@field timeout_ms? integer

---@class Media.Opts.Transcribe
---@field engine? string
---@field fallback? string[]
---@field lang? string
---@field task? "transcribe"|"translate"
---@field output? "buffer"|"sidecar"
---@field cache? boolean
---@field timeout_ms? integer
---@field normalize_timeout_ms? integer
---@field whisper_cpp? Media.Opts.Transcribe.WhisperCpp

---@class Media.Opts.Transcribe.WhisperCpp
---@field model? string

---@class Media.Opts.Cache
---@field enabled? boolean
---@field dir? string

---@class Media.Opts.Window
---@field autofit? string
---@field ontop? boolean
---@field args? string[]

---@class Media.Opts.Keymaps
---@field preset? boolean
---@field probe? string|string[]|false
---@field frame? string|string[]|false
---@field sheet? string|string[]|false
---@field play? string|string[]|false
---@field which_key? table|boolean

--- What `ffprobe` was able to say about one file.
---
--- Every field but `path`, `has_video` and `has_audio` is optional on purpose:
--- ffprobe answers about the file it was given, and a truncated download, a
--- stream without a duration and an audio file without a picture are all
--- ordinary inputs. A consumer that needs a number checks for it.
---@class Media.Probe
---@field path string
---@field container string|nil  # `format_name`, e.g. "mov,mp4,m4a,3gp,3g2,mj2"
---@field duration number|nil   # seconds
---@field size integer|nil      # bytes
---@field bitrate integer|nil   # bits per second
---@field has_video boolean  # moving picture, cover art excluded
---@field has_audio boolean
---@field has_cover boolean  # a single attached still, e.g. album art on an mp3
---@field width integer|nil     # display width, rotation already applied
---@field height integer|nil    # display height, rotation already applied
---@field rotation integer|nil  # degrees, as stored in the file
---@field fps number|nil
---@field video_codec string|nil
---@field audio_codec string|nil
---@field channels integer|nil
---@field sample_rate integer|nil

---@class Media.FrameOpts
---@field at number|string|nil  # default `frame.at`
---@field width integer|nil     # default `frame.width`

---@class Media.FramesOpts
---@field from number|string|nil  # where the run starts; seconds, "10%", or an ffmpeg timestamp. default `frames.from`
---@field count integer|nil       # how many stills. default `frames.count`
---@field fps number|nil          # stills per second of source material. default `frames.fps`
---@field width integer|nil       # pixel width before the consumer samples it into cells. default `frames.width`

--- What `media.frames` hands back so a caller can stop a decode it no longer
--- needs. `cancel()` is idempotent, and after it the callback never fires.
---@class Media.Frames.Handle
---@field cancel fun(): nil

---@class Media.SheetOpts
---@field rows integer|nil
---@field cols integer|nil
---@field width integer|nil     # width of the whole sheet
---@field margin integer|nil

---@class Media.WaveformOpts
---@field width integer|nil     # default `waveform.width`
---@field height integer|nil    # default `waveform.height`
---@field colors string|nil     # `showwavespic` only; ignored by `spectrogram`. default `waveform.colors`

--- One timed piece of a transcript. Mandatory on every engine's output, not
--- optional: without it there is no SRT/VTT and no jumping back into the
--- source at the point a line came from (ROADMAP.md, "the engine interface").
--- An engine that cannot produce real timestamps returns one segment
--- spanning the whole file — the shape stays uniform either way.
---@class Media.Segment
---@field s number  # start, seconds
---@field e number  # end, seconds
---@field text string

--- What one engine run hands back.
---@class Media.Transcript
---@field engine string
---@field model string|nil
---@field lang string|nil       # detected, or forced by the caller
---@field duration number|nil
---@field segments Media.Segment[]
---@field text string           # `segments` joined; the flat view a buffer or a sidecar shows

---@class Media.EngineCapabilities
---@field local_ boolean         # runs without a network call
---@field remote boolean
---@field segments boolean       # real per-segment timestamps, not one spanning segment
---@field translate_to_en boolean  # the engine's own `task = "translate"` support

--- What `media.core.registry.register` requires. Modelled on
--- `pdfport.core.registry`'s `Backend`, the proven shape in this ecosystem.
---@class Media.Engine
---@field id string
---@field name string
---@field capabilities Media.EngineCapabilities
---@field available fun(): boolean
---@field transcribe fun(wav_path: string, opts: Media.Engine.TranscribeOpts, callback: fun(transcript: Media.Transcript|nil, err: string|nil): nil): Media.Engine.Job

---@class Media.Engine.TranscribeOpts
---@field lang string|nil
---@field task "transcribe"|"translate"|nil
---@field model string|nil

--- What one engine call hands back so a caller can give up on it.
--- `cancel()` is idempotent, and after it the callback never fires.
---@class Media.Engine.Job
---@field cancel fun(): nil

--- What `media.transcribe` accepts.
---@class Media.TranscribeOpts
---@field engine string|nil     # default `transcribe.engine`
---@field lang string|nil       # default `transcribe.lang`
---@field task "transcribe"|"translate"|nil  # default `transcribe.task`
---@field output "buffer"|"sidecar"|nil       # default `transcribe.output`
---@field cache boolean|nil     # default `transcribe.cache`

--- What `media.transcribe` hands back: a handle that gives up on the whole
--- pipeline (WAV extraction, then the engine), not just whichever half is
--- currently running.
---@class Media.Transcribe.Handle
---@field cancel fun(): nil

---@class Media.AudioOpts
---@field at number|nil  # seconds into the file to start from; default 0
---@field paused boolean|nil  # start suspended, for a caller that will seek and resume once the socket answers

--- What `media.audio` hands back once mpv's IPC socket answers. Every method
--- is fire-and-forget except `time_pos`, which is the one thing a caller
--- cannot know without asking — mpv owns the clock.
---@class Media.Audio.Handle
---@field pause fun(): nil
---@field resume fun(): nil
---@field seek fun(seconds: number): nil
---@field time_pos fun(callback: fun(seconds: number|nil): nil): nil
---@field stop fun(): nil

---@class Media.PlayerOpts
---@field at number|string|nil  # where to start: seconds, a percentage ("50%"), or an ffmpeg timestamp — mpv's own `--start` grammar. nil or 0 is the beginning.
---@field autofit string|nil    # override `config.window.autofit` for this one window
---@field ontop boolean|nil     # override `config.window.ontop` for this one window
---@field mute boolean|nil      # start with sound off (the picture still plays)
---@field screen integer|nil    # which display `--geometry`/`--autofit-larger` resolve against; nil leaves it to mpv's own default (usually screen 0)

--- What `media.play_window` hands back: a real mpv window, and the means to
--- end it. `stop()` is idempotent and ends the whole process tree — on Windows
--- the only thing that stops mpv (see `media.core.proc`). There is no clock to
--- ask for, unlike `Media.Audio.Handle`: mpv's own window is the interface.
---@class Media.Player.Handle
---@field proc vim.SystemObj   # the `vim.system` handle, for callers that want the pid
---@field stop fun(): nil      # end the window and its process tree; idempotent
---@field stopped fun(): boolean  # whether `stop()` has been called

return {}
