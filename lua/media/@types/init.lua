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
---@field cache Media.Config.Cache
---@field player string|string[]|nil
---@field keymaps Media.Config.Keymaps

---@class Media.Config.Bin
---@field ffmpeg string|nil
---@field ffprobe string|nil
---@field mpv string|nil

---@class Media.Config.Frame
---@field at number|string  # seconds, or a percentage of the duration ("10%")
---@field width integer

---@class Media.Config.Sheet
---@field rows integer
---@field cols integer
---@field width integer
---@field margin integer
---@field timeout_ms integer

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
---@field cache? Media.Opts.Cache
---@field player? string|string[]
---@field keymaps? Media.Opts.Keymaps

---@class Media.Opts.Bin
---@field ffmpeg? string
---@field ffprobe? string
---@field mpv? string

---@class Media.Opts.Frame
---@field at? number|string
---@field width? integer

---@class Media.Opts.Sheet
---@field rows? integer
---@field cols? integer
---@field width? integer
---@field margin? integer
---@field timeout_ms? integer

---@class Media.Opts.Cache
---@field enabled? boolean
---@field dir? string

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

---@class Media.AudioOpts
---@field at number|nil  # seconds into the file to start from; default 0

--- What `media.audio` hands back once mpv's IPC socket answers. Every method
--- is fire-and-forget except `time_pos`, which is the one thing a caller
--- cannot know without asking — mpv owns the clock.
---@class Media.Audio.Handle
---@field pause fun(): nil
---@field resume fun(): nil
---@field seek fun(seconds: number): nil
---@field time_pos fun(callback: fun(seconds: number|nil): nil): nil
---@field stop fun(): nil

return {}
