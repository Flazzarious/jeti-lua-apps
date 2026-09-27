-- test_ag_dens.lua — checks ag_dens against the reference values in
-- specs/001-speed-gauge/contracts/lib-modules.md (research R1, SC-003).
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Desktop only, any Lua 5.3: run from the repo root with
--   lua tests/test_ag_dens.lua
-- Prints each result and raises an error (non-zero exit) on the first mismatch.

package.path = "src/Apps/lib/?.lua;" .. package.path
local dens = require("ag_dens")

local TOL = 0.001

local cases = {
  { "factor(0, nil)", dens.factor(0, nil), 1.0000 },
  { "factor(1524, nil)", dens.factor(1524, nil), 1.0773 },
  { "factor(1524, 35)", dens.factor(1524, 35), 1.1337 },
  { "factor(4572, 50)", dens.factor(4572, 50), 1.4097 },
  { "stdTempC(0)", dens.stdTempC(0), 15 },
  { "mToFt(ftToM(5000))", dens.mToFt(dens.ftToM(5000)), 5000 },
  { "cToF(35)", dens.cToF(35), 95 },
  { "fToC(95)", dens.fToC(95), 35 },
}

for _, c in ipairs(cases) do
  local name, got, want = c[1], c[2], c[3]
  local ok = math.abs(got - want) <= TOL
  print(string.format("%-22s got %9.4f  want %9.4f  %s", name, got, want, ok and "ok" or "FAIL"))
  if not ok then
    error(name .. " out of tolerance", 0)
  end
end
print("all " .. #cases .. " checks passed")
