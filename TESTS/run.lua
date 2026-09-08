-- TESTS/run.lua — headless test runner for media.nvim.
--
-- Run from the repo root (lib.nvim must be reachable as a sibling):
--   nvim --headless -u NONE -c "set rtp+=." -c "set rtp+=../lib.nvim" \
--        -c "luafile TESTS/run.lua" -c "qa!"
--
-- Loads every *_spec.lua listed below, runs it against the shared harness,
-- prints a per-spec result, and exits non-zero if any spec fails (`NEW-40`:
-- the runner fails loudly or it is not a gate).

local dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local H = dofile(dir .. "harness.lua")

-- The repo itself has to be on the runtimepath when invoked via `-l`, which
-- (unlike `-c "set rtp+=."`) does not add the cwd.
local repo = vim.fs.normalize(dir .. "..")
vim.opt.rtp:append(repo)
package.path = table.concat({
  repo .. "/lua/?.lua",
  repo .. "/lua/?/init.lua",
  package.path,
}, ";")

-- Order matters only at the end: smoke_spec calls setup(), which loads the
-- binding modules and registers a command. Everything before it asserts against
-- pure functions and must not depend on that having happened.
local specs = {
  "formats_spec.lua",
  "probe_spec.lua",
  "frame_args_spec.lua",
  "sheet_args_spec.lua",
  "cache_key_spec.lua",
  "ui_spec.lua",
  "smoke_spec.lua",
}

--- Straight to stdout rather than through `print`: a spec that opens a window
--- forces a redraw that swallows `print`'s pending newline, running two spec
--- results together on one line.
---@param s string
local function say(s)
  io.stdout:write(s, "\n")
end

local failed = 0
for _, name in ipairs(specs) do
  local run = dofile(dir .. name)
  local ok, err = pcall(run, H)
  if ok then
    say(("ok    %s"):format(name))
  else
    failed = failed + 1
    say(("FAIL  %s\n      %s"):format(name, tostring(err)))
  end
end

if failed > 0 then
  say(("\n%d spec(s) failed"):format(failed))
  os.exit(1)
end

say("\nMEDIA_TESTS_OK")
