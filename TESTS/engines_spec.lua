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

  H.ok(registry.has("openai_whisper"), "the built-in openai_whisper engine is registered")
  H.eq(registry.get("openai_whisper"), require("media.engines.openai_whisper"), "")
  H.ok(
    H.index_of(registry.ids(), "whisper_cpp") < H.index_of(registry.ids(), "openai_whisper"),
    "in BUILTIN order, which `:Media engines` lists"
  )

  -- Every built-in engine satisfies what `registry.register` asserts, plus
  -- the optional `ready` that `engine = "auto"` asks.
  H.ok(registry.has("faster_whisper"), "the built-in faster_whisper engine is registered")
  for _, id in ipairs({ "whisper_cpp", "faster_whisper", "openai_whisper" }) do
    local engine = registry.get(id)
    H.eq(type(engine.ready), "function", id .. " answers `ready`")
    H.eq(type(engine.capabilities), "table", id .. " declares its capabilities")
  end

  H.eq(count("whisper_cpp"), 1, "registered exactly once")
  engines.load_all()
  engines.load_all()
  H.eq(count("whisper_cpp"), 1, "calling load_all() again does not register it a second time")
  H.eq(count("openai_whisper"), 1, "")
end
