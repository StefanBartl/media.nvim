-- Every key=value pair of `:Media` has a line in lib.nvim's option float.
--
-- The text comes from the `desc` of each KvSpec in `media.bindings.usrcmds`. A new `key=` without
-- one shows up as a bare row in the cheatsheet, so this fails until it is described.
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
  for _, m in ipairs(composer.help.undocumented("Media")) do
    missing[#missing + 1] = ("%s %s"):format(m.route ~= "" and m.route or "(root)", m.name)
  end
  H.eq(#missing, 0, "every :Media option has a help text, missing: " .. table.concat(missing, ", "))
end
