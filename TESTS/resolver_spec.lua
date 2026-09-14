-- Engine resolution: the fallback chain and picking the first available one.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local registry = require("media.core.registry")
  local resolver = require("media.core.resolver")
  local config = require("media.config")

  -- ── build_chain ───────────────────────────────────────────────────────
  config.setup({ transcribe = { engine = "__resolver_spec_default", fallback = { "a", "b" } } })
  H.eq_list(
    resolver.build_chain(nil),
    { "__resolver_spec_default", "a", "b" },
    "no explicit request: the configured default, then the fallback chain"
  )
  H.eq_list(
    resolver.build_chain("explicit"),
    { "explicit", "a", "b" },
    "an explicit request replaces only the first slot"
  )

  config.setup({
    transcribe = { engine = "dup", fallback = { "dup", "b" } },
  })
  H.eq_list(
    resolver.build_chain(nil),
    { "dup", "b" },
    "a fallback entry equal to the first slot is not repeated"
  )

  -- ── resolve: first available wins ────────────────────────────────────
  local unavailable = {
    id = "__resolver_spec_unavailable",
    available = function()
      return false
    end,
    transcribe = function() end,
  }
  local available = {
    id = "__resolver_spec_available",
    available = function()
      return true
    end,
    transcribe = function() end,
  }
  registry.register(unavailable)
  registry.register(available)

  config.setup({
    transcribe = {
      engine = unavailable.id,
      fallback = { available.id },
    },
  })
  local resolved, err = resolver.resolve(nil)
  H.eq(resolved, available, "the unavailable default is skipped for the available fallback")
  H.eq(err, nil, "no error once something resolved")

  -- ── resolve: nothing available reports the whole chain it tried ──────
  config.setup({ transcribe = { engine = unavailable.id, fallback = {} } })
  local none, none_err = resolver.resolve(nil)
  H.eq(none, nil, "no engine resolves")
  H.match(none_err, unavailable.id, "the error names what was tried")

  -- ── resolve: an unregistered id in the chain is skipped, not fatal ───
  config.setup({ transcribe = { engine = "__does_not_exist", fallback = { available.id } } })
  local skipped = resolver.resolve(nil)
  H.eq(skipped, available, "an id with nothing registered for it is passed over")

  -- Leave global config as the tests found it — later specs must not see
  -- this spec's fake engine ids.
  config.setup({})
end
