-- TESTS/harness.lua — tiny assertion helper shared by the spec files.
-- Returned to each spec by TESTS/run.lua.
--
-- Framework-free on purpose (`NEW-40`): the point of this suite is that it
-- catches load errors and argument-order regressions on a runner with no
-- ffmpeg, no lib.nvim UI and no plenary. Anything that needed a plugin manager
-- to run would not run in CI, which is the only place it has to.

local H = {}

--- Assert equality; raises a descriptive error on mismatch (caught by the runner).
---@param a any # actual
---@param b any # expected
---@param msg string|nil
function H.eq(a, b, msg)
  if a ~= b then
    error(("FAIL %s: expected %q, got %q"):format(msg or "", tostring(b), tostring(a)), 2)
  end
end

--- Assert a truthy value.
---@param v any
---@param msg string|nil
function H.ok(v, msg)
  if not v then error(("FAIL %s: expected truthy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert a falsy value.
---@param v any
---@param msg string|nil
function H.falsy(v, msg)
  if v then error(("FAIL %s: expected falsy, got %q"):format(msg or "", tostring(v)), 2) end
end

--- Assert `s` matches Lua pattern `pat`.
---@param s string
---@param pat string
---@param msg string|nil
function H.match(s, pat, msg)
  if not tostring(s):match(pat) then
    error(("FAIL %s: %q does not match pattern %q"):format(msg or "", tostring(s), pat), 2)
  end
end

--- Assert two list-like tables are element-wise equal.
---@param a any[]|nil
---@param b any[]
---@param msg string|nil
function H.eq_list(a, b, msg)
  if type(a) ~= "table" then
    error(("FAIL %s: expected a table, got %q"):format(msg or "", tostring(a)), 2)
  end
  if #a ~= #b then
    error(
      ("FAIL %s: expected %d element(s) {%s}, got %d {%s}"):format(
        msg or "",
        #b,
        table.concat(b, ","),
        #a,
        table.concat(a, ",")
      ),
      2
    )
  end
  for i = 1, #b do
    if a[i] ~= b[i] then
      error(
        ("FAIL %s: index %d expected %q, got %q"):format(
          msg or "",
          i,
          tostring(b[i]),
          tostring(a[i])
        ),
        2
      )
    end
  end
end

--- The index of `needle` in list `haystack`, or nil.
---
--- Every argument-order assertion in this suite is really a statement about
--- relative position — `-ss` before `-i`, `-skip_frame` before `-i` — so the
--- specs need positions, not membership.
---@param haystack string[]
---@param needle string
---@return integer|nil
function H.index_of(haystack, needle)
  for i, v in ipairs(haystack) do
    if v == needle then return i end
  end
  return nil
end

--- Assert `first` appears before `second` in `list`, and that both are present.
---@param list string[]
---@param first string
---@param second string
---@param msg string|nil
function H.before(list, first, second, msg)
  local i, j = H.index_of(list, first), H.index_of(list, second)
  if not i then error(("FAIL %s: %q is not in the list"):format(msg or "", first), 2) end
  if not j then error(("FAIL %s: %q is not in the list"):format(msg or "", second), 2) end
  if i >= j then
    error(
      ("FAIL %s: %q (at %d) is not before %q (at %d)"):format(msg or "", first, i, second, j),
      2
    )
  end
end

--- A decoded ffprobe document for a landscape h264 video with stereo audio.
--- Written out rather than captured from a file so the specs stay readable and
--- so a field can be removed to test the "ffprobe said nothing" branches.
---@param overrides table|nil merged over the video stream
---@return table
function H.ffprobe_video(overrides)
  local stream = {
    codec_type = "video",
    codec_name = "h264",
    width = 1920,
    height = 1080,
    avg_frame_rate = "30000/1001",
    r_frame_rate = "30/1",
    disposition = {},
  }
  for k, v in pairs(overrides or {}) do
    stream[k] = v
  end
  return {
    format = {
      format_name = "mov,mp4,m4a,3gp,3g2,mj2",
      duration = "272.360000",
      size = "104857600",
      bit_rate = "3080000",
    },
    streams = {
      stream,
      {
        codec_type = "audio",
        codec_name = "aac",
        channels = 2,
        sample_rate = "48000",
        disposition = {},
      },
    },
  }
end

return H
