-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "media",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "h",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next).
  isolated = "file",
  -- Safety nets (testing.nvim docs/GUARDS.md). With "file" the setup() state of smoke_spec (the
  -- MediaNvim autocmd group, :Media, the \M* keymaps) stays in that file's own nvim, so the state
  -- guard is silent and runs in "error" mode like all the others: the suite is clean under them.
  guards = {
    fs = "error",
    state = "error",
    scheduled_error = "error",
    prompt = "error",
    deprecation = "error",
    process_net = "error",
  },
  guard_allow = {
    -- Executables a spec may start on purpose.
    spawn = {
      -- health_spec runs the real `ffmpeg -version` through the plugin's health check.
      "ffmpeg",
      -- probe_spec starts a deliberately nonexistent binary to cover the "tool missing" path.
      "does-not-exist",
    },
  },
}
