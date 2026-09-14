-- The transcription-engine registry: register/get/all/ids/has.
---@diagnostic disable: need-check-nil, missing-fields, missing-return

---@param H table
return function(H)
  local registry = require("media.core.registry")

  ---@type Media.Engine
  local fake = {
    id = "__registry_spec_fake",
    name = "fake",
    capabilities = { local_ = true, remote = false, segments = false, translate_to_en = false },
    available = function()
      return true
    end,
    transcribe = function(_, _, cb)
      cb(nil, "not implemented")
    end,
  }

  H.falsy(registry.has(fake.id), "not registered yet")
  registry.register(fake)
  H.ok(registry.has(fake.id), "registered")
  H.eq(registry.get(fake.id), fake, "get() returns the same table registered")

  -- Registering the same id again does not duplicate it in `ids()`/`all()`.
  registry.register(fake)
  local count = 0
  for _, id in ipairs(registry.ids()) do
    if id == fake.id then count = count + 1 end
  end
  H.eq(count, 1, "re-registering the same id is idempotent, not a duplicate")

  local found = false
  for _, engine in ipairs(registry.all()) do
    if engine.id == fake.id then found = true end
  end
  H.ok(found, "all() includes it")

  -- ── invalid registrations raise ──────────────────────────────────────
  local ok1 =
    pcall(registry.register, { id = "", available = function() end, transcribe = function() end })
  H.falsy(ok1, "an empty id is rejected")

  local ok2 = pcall(registry.register, { id = "x", transcribe = function() end })
  H.falsy(ok2, "a missing available() is rejected")

  local ok3 = pcall(registry.register, { id = "x", available = function() end })
  H.falsy(ok3, "a missing transcribe() is rejected")
end
