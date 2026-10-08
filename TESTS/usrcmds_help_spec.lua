-- Every key=value pair and positional argument of `:Media` has a line in lib.nvim's option float.
--
-- The text comes from the `desc` of each KvSpec/ArgSpec in `media.bindings.usrcmds` (the
-- dashboard's `scope`), or from the `desc` of the MEDIA_PATH type, written once for the `[path]` of
-- every route. A new `key=` or argument without one shows up as a bare row in the cheatsheet, so
-- this fails until it is described.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local ok, composer = pcall(require, "lib.nvim.bindings.usercmd.composer")
  H.ok(ok, "the composer loads")

  -- A lib.nvim older than `help.undocumented` cannot answer the question; that is a missing
  -- feature of the dependency, not a defect of this plugin.
  if type(composer.help.undocumented) ~= "function" then return end

  require("media.bindings.usrcmds").register()
  H.ok(composer.registry().Media ~= nil, ":Media is registered through the composer")

  local missing = {}
  for _, m in ipairs(composer.help.undocumented("Media", { args = true })) do
    missing[#missing + 1] = ("%s %s"):format(m.route ~= "" and m.route or "(root)", m.name)
  end
  H.eq(
    #missing,
    0,
    "every :Media option and argument has a help text, missing: " .. table.concat(missing, ", ")
  )

  -- The texts keep the shape the float expects: one short line, no trailing full stop. Every text
  -- an argument can bring: its own `desc`, the `desc` of its type, its `enum_desc` values.
  local argtypes = require("lib.nvim.bindings.usercmd.composer.argtypes")
  local seen = 0
  local function check(text, what)
    seen = seen + 1
    H.ok(type(text) == "string" and text ~= "", what .. " shows a text")
    H.falsy(text:find("\n", 1, true), what .. " is one line")
    H.ok(#text <= 80, what .. " stays short")
    H.falsy(text:find("%.$"), what .. " has no trailing full stop")
  end
  for _, route in ipairs(composer.registry().Media:spec().routes or {}) do
    for _, arg in ipairs(route.args or {}) do
      local path = table.concat(route.path, " ")
      local what = ("argument %s of :Media %s"):format(arg.name, path ~= "" and path or "(root)")
      if arg.desc then check(arg.desc, what) end
      local def = arg.type and argtypes.get(arg.type)
      if def and def.desc then check(def.desc, ("type %s of %s"):format(arg.type, what)) end
      for value, text in pairs(arg.enum_desc or {}) do
        check(text, ("value %s of %s"):format(value, what))
      end
    end
  end
  H.ok(seen > 0, "the routes' arguments were actually walked")
end
