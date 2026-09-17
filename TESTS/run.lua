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

-- Order matters at both ends: config_spec asserts about the state of
-- `media.config` before anything has ever called `setup()`, so it has to run
-- before any other spec that does (nearly all of them). At the other end,
-- smoke_spec calls setup(), which loads the binding modules and registers a
-- command; everything before it asserts against pure functions and must not
-- depend on that having happened.
local specs = {
  "config_spec.lua",
  "formats_spec.lua",
  "probe_spec.lua",
  "frame_args_spec.lua",
  "frames_args_spec.lua",
  "sheet_args_spec.lua",
  "waveform_args_spec.lua",
  "normalize_args_spec.lua",
  "whisper_cpp_spec.lua",
  "hub_kinds_spec.lua",
  "hub_scan_spec.lua",
  "hub_text_spec.lua",
  "segments_spec.lua",
  "srt_spec.lua",
  "vtt_spec.lua",
  "sidecar_spec.lua",
  "registry_spec.lua",
  "resolver_spec.lua",
  "audio_args_spec.lua",
  "player_args_spec.lua",
  "proc_spec.lua",
  "cache_key_spec.lua",
  "ui_spec.lua",
  "bin_spec.lua",
  "play_spec.lua",
  "engines_spec.lua",
  "output_spec.lua",
  "dispatcher_spec.lua",
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
