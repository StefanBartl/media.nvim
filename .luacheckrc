-- luacheck configuration for media.nvim
std = "luajit"
read_globals = { "vim" }

-- The plugin-load guard writes vim.g.loaded_media. Assigning through vim.g is
-- the documented API, but luacheck reads the whole `vim` table as read-only
-- and flags it, so the writable sub-tables are declared explicitly.
globals = { "vim.g", "vim.b", "vim.bo", "vim.wo", "vim.opt" }

-- The codebase favours readability over an 80/120 column cap; stylua already
-- enforces a 100-column target where it can break lines safely.
max_line_length = false

-- `NEW-49`: luacheck's built-in busted detection matches `**/spec/**`,
-- `**/test/**` and `**/tests/**` — all lowercase. `TESTS/` matches none of
-- them. This suite is framework-free anyway (see TESTS/harness.lua), so what
-- it needs is not busted globals but permission to stub `vim.*` fields.
files["TESTS/"] = {
  ignore = {
    "122", -- setting a read-only field of a global (vim.*)
  },
}
