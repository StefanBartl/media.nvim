-- Engine resolution: the fallback chain and picking the first available one.
---@diagnostic disable: need-check-nil, missing-fields

---@param H table
return function(H)
  local registry = require("media.core.registry")
  local resolver = require("media.core.resolver")
  local config = require("media.config")

  local fake_ids = {
    "__resolver_spec_unavailable",
    "__resolver_spec_available",
    "__resolver_spec_not_ready",
  }

  -- The fakes live in the process-wide registry: they are removed again whatever the checks below
  -- do, so a failure in the middle cannot leave them behind for the specs that run after this one.
  local body_ok, body_err = pcall(function()
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

    -- ── "auto": the configured order, then the fallback, no duplicates ──
    config.setup({ transcribe = { engine = "auto", auto = { "x", "y" }, fallback = { "y", "z" } } })
    H.eq_list(resolver.build_chain(nil), { "x", "y", "z" }, "auto expands to its list")
    H.eq_list(resolver.build_chain("auto"), { "x", "y", "z" }, "as an explicit request too")
    H.eq_list(
      resolver.build_chain("x"),
      { "x", "y", "z" },
      "an explicit id is not expanded; a fallback equal to it is still dropped"
    )

    -- ── "auto" passes over an engine that is installed but not ready ─────
    local seen_opts
    local not_ready = {
      id = "__resolver_spec_not_ready",
      available = function()
        return true
      end,
      ready = function(opts)
        seen_opts = opts
        return false, "no model configured"
      end,
      transcribe = function() end,
    }
    registry.register(not_ready)
    config.setup({
      transcribe = { engine = "auto", auto = { not_ready.id, available.id } },
    })
    H.eq(
      resolver.resolve(nil, { model = "medium" }),
      available,
      "auto skips the engine that cannot run and takes the next ready one"
    )
    H.eq(seen_opts and seen_opts.model, "medium", "ready() is asked about the requested model")

    -- An explicit request keeps the plain available() test, so the engine's
    -- own, specific error reaches the user rather than a silent switch.
    config.setup({ transcribe = { engine = not_ready.id, fallback = { available.id } } })
    H.eq(resolver.resolve(nil), not_ready, "an explicitly chosen engine is not second-guessed")

    -- ── "auto" with nothing ready says why, per engine ───────────────────
    config.setup({ transcribe = { engine = "auto", auto = { not_ready.id, unavailable.id } } })
    local nothing, why = resolver.resolve(nil)
    H.eq(nothing, nil, "")
    H.match(why, "no model configured", "the not-ready reason is in the error")
    H.match(why, unavailable.id .. ": not installed", "and the uninstalled one is named as such")
  end)

  -- Leave global config and registry as the tests found them — later specs must not see
  -- this spec's fake engines.
  config.setup({})
  for _, id in ipairs(fake_ids) do
    registry.unregister(id)
  end
  for _, id in ipairs(registry.ids()) do
    H.falsy(id:sub(1, 2) == "__", "no fake engine is left in the registry: " .. id)
  end
  assert(body_ok, body_err)
end
