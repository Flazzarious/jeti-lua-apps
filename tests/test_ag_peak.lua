-- test_ag_peak.lua — checks ag_peak's spike filter against
-- specs/005-battery-capacity/contracts/lib-modules.md (research R7, SC-010).
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Desktop only, any Lua 5.3: run from the repo root with
--   lua tests/test_ag_peak.lua
-- Prints each result and raises an error (non-zero exit) on the first mismatch.

package.path = "src/Apps/lib/?.lua;" .. package.path
local peak = require("ag_peak")

-- Feeds readings `step` ms apart and returns the max after the last one.
local function run(values, step)
  local st, t = peak.new(), 0
  for _, v in ipairs(values) do
    t = t + (step or 200)
    peak.update(st, v, t)
  end
  return st.max
end

local cases = {
  -- a one-sample spike never becomes the max; the lower of two counts
  { "spike among 40s", run({ 10, 20, 30, 40, 150, 41, 42 }), 41 },
  -- the same spike read twice (the loop is faster than the sensor), then gone
  { "spike read twice", run({ 40, 150, 150, 40 }), 40 },
  -- a real peak held for a while registers
  { "held peak", run({ 50, 70, 92, 92, 92, 92, 92, 92, 80 }), 92 },
  -- a steady value from power-up registers once it has held 1 s
  { "steady, 0.8 s", run({ 40, 40, 40, 40, 40 }), 0 },
  { "steady, 1.2 s", run({ 40, 40, 40, 40, 40, 40, 40 }), 40 },
}

for _, c in ipairs(cases) do
  local name, got, want = c[1], c[2], c[3]
  print(string.format("%-18s %6.1f (want %.1f)", name, got, want))
  assert(got == want, name .. ": got " .. got .. ", want " .. want)
end

-- reset clears the max and the pending reading
local st = peak.new()
peak.update(st, 50, 0)
peak.update(st, 60, 200)
assert(st.max == 50, "two distinct readings: the lower counts")
peak.reset(st)
assert(st.max == 0 and st.prev == nil, "reset")
local _, rose = peak.update(st, 30, 400)
assert(not rose, "first reading after reset doesn't count yet")
print("reset              ok")
print("ag_peak OK")
