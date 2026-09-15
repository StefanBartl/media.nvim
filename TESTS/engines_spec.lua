-- media.engines: registers the built-in engine list into the registry, once.
---@diagnostic disable: need-check-nil

---@param H table
return function(H)
  local engines = require("media.engines")
  local registry = require("media.core.registry")

  engines.load_all()
  H.ok(registry.has("whisper_cpp"), "the built-in whisper_cpp engine is registered")
  H.eq(
    registry.get("whisper_cpp"),
    require("media.engines.whisper_cpp"),
    "the registered entry is the real module, not a copy"
  )

  local function count(id)
    local n = 0
    for _, existing in ipairs(registry.ids()) do
      if existing == id then n = n + 1 end
    end
    return n
  end

  H.eq(count("whisper_cpp"), 1, "registered exactly once")
  engines.load_all()
  engines.load_all()
  H.eq(count("whisper_cpp"), 1, "calling load_all() again does not register it a second time")
end
