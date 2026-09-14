-- The shared transcript model's one helper: flattening segments to text.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local segments = require("media.core.segments")

  H.eq(
    segments.to_text({
      { s = 0, e = 1, text = "Hello" },
      { s = 1, e = 2, text = "world." },
    }),
    "Hello world.",
    "segments join with a single space, in order"
  )

  H.eq(segments.to_text({}), "", "no segments is empty text, not an error")
end
