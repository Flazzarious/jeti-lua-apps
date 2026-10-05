-- ag_dens.lua — air density correction (ISA troposphere) and unit conversions.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Shared module (constitution VII): pure functions, no state. Safe to call
-- from anywhere. True airspeed = indicated (sensor) speed * factor(...).

local M = {}

local T0 = 288.15      -- ISA sea-level temperature, K
local LAPSE = 0.0065   -- ISA lapse rate, K/m
local EXP = 5.25588    -- g / (R * lapse) for the pressure ratio
local FT = 0.3048      -- meters per foot

-- Standard-atmosphere temperature (°C) at an elevation in meters.
function M.stdTempC(elevM)
  return 15 - LAPSE * elevM
end

-- Correction factor k = 1 / sqrt(density ratio). tempC nil = standard day.
function M.factor(elevM, tempC)
  local ts = T0 - LAPSE * elevM
  local delta = (ts / T0) ^ EXP
  local t = ts
  if tempC then
    t = tempC + 273.15
  end
  local sigma = delta * T0 / t
  return 1 / math.sqrt(sigma)
end

function M.ftToM(ft)
  return ft * FT
end

function M.mToFt(m)
  return m / FT
end

function M.fToC(f)
  return (f - 32) * 5 / 9
end

function M.cToF(c)
  return c * 9 / 5 + 32
end

return M
