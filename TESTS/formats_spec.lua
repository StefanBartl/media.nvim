-- What the plugin claims by extension.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local formats = require("media.formats")

  H.ok(formats.is_video("/tmp/clip.mp4"), "mp4")
  H.ok(formats.is_video("C:/Users/x/Video.MKV"), "the check is case-insensitive")
  H.ok(formats.is_audio("~/music/song.flac"), "flac")
  H.ok(formats.is_media("song.opus"), "is_media covers both lists")

  H.falsy(formats.is_video("song.mp3"), "audio is not video")
  H.falsy(formats.is_media("notes.md"), "and text is neither")
  H.falsy(formats.is_media(nil), "nil is not a media file")
  H.falsy(formats.is_media(""), "nor is the empty string")
  H.falsy(formats.is_media("/tmp/mp4"), "an extension is not a filename")

  -- A path lifted out of a markdown link routinely carries a trailing space,
  -- and rejecting it would make the commands fail exactly where they are most
  -- useful.
  H.ok(formats.is_video("clip.mp4 "), "a trailing space is tolerated")

  H.eq(formats.extension("A.Movie.2019.mkv"), "mkv", "only the last dot counts")
  H.eq(formats.extension("noext"), nil, "no dot, no extension")

  local video, audio = formats.known()
  H.ok(#video > 0 and #audio > 0, "both lists are populated")
  H.eq(video[1], video[1]:lower(), "and lowercase")
  local sorted = true
  for i = 2, #video do
    sorted = sorted and video[i - 1] < video[i]
  end
  H.ok(sorted, "known() is sorted, so two callers print it the same way")
end
