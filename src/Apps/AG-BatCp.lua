-- AG-BatCp.lua — Battery Capacity: up to four battery gauges with capacity, voltage and current callouts.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Listen-and-inform only: it reads telemetry sensors, plays speech and
-- draws. It never controls the model or changes a transmitter setting
-- (constitution principle I, FR-036). Voice files in /Apps/AG-BatCp/voice/
-- are licensed CC BY-SA 4.0 (Piper "Amy" voice), not MIT (FR-035).
--
-- Design: specs/005-battery-capacity/ (plan.md, research.md, data-model.md,
-- contracts/). Research decisions are cited as R1..R14.

local APP_NAME = "Battery Capacity"
local APP_VERSION = "0.1.0"
local peak = require("ag_peak")

-- Debug switches, both off for release (R13).
local DEBUG_CPU = false     -- show per-call CPU in the double window, log loop CPU
local SIM = false           -- replace battery 1's sensors with scripted profiles

-- Timing (R2, R4).
local T = {
  FAST = 200,               -- sensor reads, alarm timers, max filter
  SLOW = 1000,              -- %, bands, callouts, display strings (FR-014)
  LOST = 1000,              -- capacity source invalid this long = telemetry lost
  NEWPACK = 20,             -- % points higher after a loss = new pack
  HYST = 5,                 -- callout re-arm margin, % points (FR-017)
  NP_DELAY = 3000,          -- new-pack check after the pack is first seen (FR-029)
  VWAIT = 3000,             -- an mAh pack waits this long for its starting voltage
}

-- The JETI Studio emulator draws each window's title inside the reported
-- canvas (157 x 127 / 157 x 60); the transmitter draws it above and reports
-- 150 x 68 / 150 x 23 (Speed Gauge, 2026-10-03).
local TITLE_H = 26

local TXT = {
  noTel = "NO TELEM", no = "NO", telem = "TELEM", dash = "--",
  noBat = "Add a battery in settings", needs = "Gauges need a DS/DC-24",
}

------------------------------------------------------------------------------
-- Constant tables (data-model.md)
------------------------------------------------------------------------------

-- Categories by fixed id: ids never change or get reused (FR-002). `short`
-- replaces the label when the numbered label doesn't fit its slot (R6).
-- `cur` = current-alarm rows shown without "Show all" (FR-007).
local CAT = {
  { name = "Flight pack", label = "FLIGHT", short = "FLT", voice = "n_flt", chem = 1,
    bands = { 50, 30, 20 }, levels = { 50, 40, 30, 20 }, cur = true, maxOn = 1 },
  { name = "Receiver", label = "RX", voice = "n_rx", chem = 4,
    bands = { 60, 45, 30 }, levels = { 60, 50, 40, 30 }, cur = true, maxOn = 0 },
  { name = "Turbine ECU", label = "ECU", voice = "n_ecu", chem = 4,
    bands = { 60, 45, 30 }, levels = { 60, 50, 40, 30 }, cur = false, maxOn = 0 },
  { name = "Landing gear", label = "GEAR", voice = "n_gear", chem = 4,
    bands = { 55, 40, 30 }, levels = { 60, 50, 40, 30 }, cur = true, maxOn = 0 },
  { name = "Brakes", label = "BRAKES", short = "BRK", voice = "n_brk", chem = 4,
    bands = { 55, 40, 30 }, levels = { 60, 50, 40, 30 }, cur = true, maxOn = 0 },
  { name = "Lights", label = "LIGHTS", short = "LGT", voice = "n_lgt", chem = 1,
    bands = { 40, 20, 10 }, levels = { 40, 30, 20, 10 }, cur = false, maxOn = 0 },
  { name = "Aux", label = "AUX", voice = "n_aux", chem = 1,
    bands = { 50, 30, 20 }, levels = { 50, 40, 30, 20 }, cur = true, maxOn = 0 },
  { name = "Custom", label = "", voice = "n_bat", chem = 1,
    bands = { 50, 30, 20 }, levels = { 50, 40, 30, 20 }, cur = true, maxOn = 0 },
}
local CUSTOM = 8
local CAT_ORDER = { 1, 2, 3, 6, 5, 4, 7, 8 }   -- menu order (spec Terms)

-- Chemistries: per-cell voltages in centivolts (FR-006). Full is the charge
-- voltage, used only for the cell-count check (R3, R11).
local CHEM = {
  { name = "LiPo", full = 420, nom = 370, warn = 360, cut = 350 },
  { name = "LiHV", full = 435, nom = 380, warn = 365, cut = 350 },
  { name = "Li-ion", full = 420, nom = 360, warn = 340, cut = 320 },
  { name = "LiFe", full = 360, nom = 330, warn = 320, cut = 300 },
  { name = "NiMH/NiCd", full = 140, nom = 120, warn = 115, cut = 110 },
}
local CHEM_NAMES = { "LiPo", "LiHV", "Li-ion", "LiFe", "NiMH/NiCd" }

-- Resting voltage per cell (cV) at 100, 90, ..., 0 % (R3). UNVERIFIED
-- typical values; bench-checked in quickstart B1.
local CURVE = {
  { 420, 411, 402, 395, 387, 384, 380, 377, 373, 369, 350 },
  { 435, 425, 416, 408, 400, 395, 390, 386, 381, 375, 350 },
  { 420, 408, 398, 389, 381, 374, 367, 361, 355, 345, 320 },
  { 340, 334, 332, 331, 330, 329, 327, 325, 322, 315, 300 },
  { 140, 133, 130, 128, 127, 126, 125, 123, 121, 117, 110 },
}

-- Band colours and the text colour on each (FR-012b, FR-013). 1 green ..
-- 4 red.
local BAND = {
  { 99, 153, 34 }, { 242, 194, 48 }, { 239, 159, 39 }, { 226, 75, 74 },
}
local BAND_TXT = {
  { 255, 255, 255 }, { 65, 36, 2 }, { 255, 255, 255 }, { 255, 255, 255 },
}
local RED = { 226, 75, 74 }  -- low-voltage flash (FR-022)

-- FONT_MINI widths in Lua px, for the label fit check (R6). Measured on
-- the DS-24 II with PROBE MODE 6 (Screen034, 2026-11-04). Single characters
-- read rounded down: whole words measure about 0.6 px per character more
-- ("FLIGHT-2" 33 summed, 38 measured), so labelWidth adds MINI_W_EXTRA.
-- Characters not measured (lower case, punctuation) count as 7.
local MINI_W = {
  A = 6, B = 5, C = 6, D = 6, E = 4, F = 4, G = 6, H = 6, I = 2, J = 4, K = 5, L = 4, M = 7,
  N = 6, O = 6, P = 5, Q = 6, R = 5, S = 5, T = 5, U = 5, V = 5, W = 7, X = 5, Y = 5, Z = 5,
  ["0"] = 4, ["1"] = 4, ["2"] = 4, ["3"] = 4, ["4"] = 4, ["5"] = 4, ["6"] = 4, ["7"] = 4,
  ["8"] = 4, ["9"] = 4, ["-"] = 2, [" "] = 2, ["%"] = 6,
}
local MINI_W_OTHER = 7
local MINI_W_EXTRA = 0.6

-- Layout (contracts/telemetry-window.md), transmitter coordinates.
local L = {
  slotW = 37,               -- double window: one battery slot
  minFill = 2, minFillPct = 2,   -- 0-2 %: fill at least 2 px so the colour shows (FR-012)
  -- small window: battery on its side
  sx = 1, sy = 1, sw = 82, sh = 21, capX = 83, capY = 7, capW = 3, capH = 9,
  sfx = 3, sfy = 3, sfw = 78, sfh = 17, sPctY = 2, stx = 90, sLabelY = -1, sValY = 10,
  -- double window: upright batteries, offsets within a slot
  dLabelY = 0, dCapW = 10, dCapY = 12, dCapH = 3, dx = 5, dy = 15, dw = 26, dh = 40,
  dfx = 7, dfw = 22, dfBottom = 53, dfh = 36, dPctY = 40, dLineY = 56, dNoY = 24, dTelY = 36,
}

------------------------------------------------------------------------------
-- Settings (persisted per model; data-model.md "Saved settings"). Per
-- battery: an int array for the pack, one for alarms, and a string array.
------------------------------------------------------------------------------

-- Field indexes. P = pack array, A = alarms array, S = string array.
local P = {
  CAT = 1, NUM = 2, CHEM = 3, CELLS = 4, MAH = 5, CAPID = 6, CAPPAR = 7, CAPMODE = 8,
  VID = 9, VPAR = 10, IID = 11, IPAR = 12, VFULL = 13, VNOM = 14, VWARN = 15, VCUT = 16,
  BANDY = 17, BANDO = 18, BANDR = 19, EDITED = 20, N = 20,
}
local A = {
  LVL1 = 1, LVLON = 5, RPT = 6, MAXCNT = 7, LVMODE = 8, LVTHR = 9, LVDLY = 10,
  ITHR = 11, IDLY = 12, IRPT = 13, MAXON = 14, MAXSENS = 15, NPON = 16, NPTHR = 17,
  SHOWALL = 18, N = 18,
}
local S = { NAME = 1, VOICE = 2, CAPLBL = 3, VLBL = 4, ILBL = 5, N = 5 }

-- Edited-mask bits (FR-008) and the "current sensor reports mA" flag.
local E = { VOLT = 1, BAND = 2, LVL = 4, LVTHR = 8, MA = 0x8000 }

-- Capacity modes (R1).
local M = { NONE = 0, MAH = 1, AH = 2, PCT = 3, VOLT = 4 }
local CAP_UNITS = { mAh = M.MAH, Ah = M.AH, ["%"] = M.PCT, V = M.VOLT }

-- Receiver voltages aren't in getSensors() on the transmitter; they come
-- from getTxTelemetry(). Saved as sensor id RXV, param 1-3 (R1). The
-- voltage keeps its last value after a link loss; Q drops to 0.
local RXV = -1
local RXV_LABEL = { "Receiver 1 voltage", "Receiver 2 voltage", "Backup Rx voltage" }
local RXV_FIELD = { "rx1Voltage", "rx2Voltage", "rxBVoltage" }
local RXV_Q = { "rx1Percent", "rx2Percent", "rxBPercent" }

-- Clamp ranges on load; nil = not clamped (sensor ids).
local P_RANGE = {
  [1] = { 1, 99 }, [2] = { 0, 9 }, [3] = { 1, 5 }, [4] = { 1, 14 }, [5] = { 0, 30000 },
  [8] = { 0, 4 }, [13] = { 50, 500 }, [14] = { 50, 500 }, [15] = { 50, 500 }, [16] = { 50, 500 },
  [17] = { 1, 99 }, [18] = { 1, 99 }, [19] = { 1, 99 }, [20] = { 0, 65535 },
}
local A_RANGE = {
  [1] = { 1, 99 }, [2] = { 1, 99 }, [3] = { 1, 99 }, [4] = { 1, 99 }, [5] = { 0, 15 },
  [6] = { 3, 60 }, [7] = { 0, 20 }, [8] = { 0, 2 }, [9] = { 50, 9999 }, [10] = { 5, 100 },
  [11] = { 0, 500 }, [12] = { 0, 100 }, [13] = { 0, 60 }, [14] = { 0, 1 }, [15] = { 1, 50 },
  [16] = { 0, 1 }, [17] = { 50, 99 }, [18] = { 0, 1 },
}

local KEY = {
  p = { "b1p", "b2p", "b3p", "b4p" }, a = { "b1a", "b2a", "b3a", "b4a" },
  s = { "b1s", "b2s", "b3s", "b4s" },
}

-- Window titles (FR-009a): "" means the default.
local TITLE = { "Battery", "Batteries" }
local TITLE_MAX = 20

local cfg = { cfgV = 1, voice = 0, numOnly = 0, smallB = 1, title1 = "", title2 = "" }   -- app keys
local bat = {}              -- bat[k] = { p = {...}, a = {...}, s = {...} }, k = 1..#bat

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

local function catOf(id)
  return CAT[id] or CAT[CUSTOM]
end

local function catName(id)
  if CAT[id] then
    return CAT[id].name
  end
  return "Unknown (" .. id .. ")"
end

local function saveApp(key, value)
  cfg[key] = value
  system.pSave(key, value)
end

local function saveBattery(k)
  local b = bat[k]
  system.pSave(KEY.p[k], b.p)
  system.pSave(KEY.a[k], b.a)
  system.pSave(KEY.s[k], b.s)
end

local function clearSlot(k)
  system.pSave(KEY.p[k], nil)
  system.pSave(KEY.a[k], nil)
  system.pSave(KEY.s[k], nil)
end

-- Per-cell voltage defaults and the low-voltage threshold that follows them.
local function fillVoltages(p)
  local c = CHEM[p[P.CHEM]]
  p[P.VFULL], p[P.VNOM], p[P.VWARN], p[P.VCUT] = c.full, c.nom, c.warn, c.cut
end

local function defaultLvThr(b)
  if b.a[A.LVMODE] == 2 then
    return b.p[P.VWARN] * b.p[P.CELLS]
  end
  return b.p[P.VWARN]
end

local function fillBands(p, c)
  p[P.BANDY], p[P.BANDO], p[P.BANDR] = c.bands[1], c.bands[2], c.bands[3]
end

local function fillLevels(a, c)
  for i = 1, 4 do
    a[A.LVL1 + i - 1] = c.levels[i]
  end
end

-- A battery with category `cat`'s defaults (data-model.md).
local function newBattery(cat)
  local c = catOf(cat)
  local p = {}
  for i = 1, P.N do
    p[i] = 0
  end
  p[P.CAT], p[P.CHEM], p[P.CELLS] = cat, c.chem, 2
  fillVoltages(p)
  fillBands(p, c)
  local a = {}
  for i = 1, A.N do
    a[i] = 0
  end
  fillLevels(a, c)
  a[A.LVLON] = 8            -- slot 4, the lowest, only (FR-016)
  a[A.RPT], a[A.LVMODE], a[A.LVDLY] = 5, 1, 20
  a[A.MAXON], a[A.MAXSENS], a[A.NPTHR] = c.maxOn, 5, 90
  local b = { p = p, a = a, s = { "", "", "", "", "" } }
  a[A.LVTHR] = defaultLvThr(b)
  return b
end

-- Fills fields missing from an older or shorter array with defaults.
local function pad(arr, defaults)
  for i = 1, #defaults do
    if type(arr[i]) ~= type(defaults[i]) then
      arr[i] = defaults[i]
    end
  end
end

local function clampArray(arr, ranges)
  local changed = false
  for i, r in pairs(ranges) do
    local v = clamp(arr[i], r[1], r[2])
    if v ~= arr[i] then
      arr[i], changed = v, true
    end
  end
  return changed
end

-- Load rules (data-model.md): defaults for missing keys, clamp and save
-- back, compact empty slots so batteries 1..n are contiguous.
local function loadSettings()
  cfg.cfgV = system.pLoad("cfgV", 1)
  cfg.voice = clamp(system.pLoad("voice", 0), 0, 2)
  cfg.numOnly = clamp(system.pLoad("numOnly", 0), 0, 1)
  cfg.smallB = system.pLoad("smallB", 1)
  for n = 1, 2 do
    local t = system.pLoad("title" .. n, "")
    if type(t) ~= "string" then
      t = ""
    end
    cfg["title" .. n] = string.sub(t, 1, TITLE_MAX)
  end
  bat = {}
  local compacted = false
  for k = 1, 4 do
    local p = system.pLoad(KEY.p[k])
    if type(p) == "table" and type(p[P.CAT]) == "number" then
      local def = newBattery(p[P.CAT])
      local a = system.pLoad(KEY.a[k])
      local s = system.pLoad(KEY.s[k])
      if type(a) ~= "table" then
        a = def.a
      end
      if type(s) ~= "table" then
        s = def.s
      end
      pad(p, def.p)
      pad(a, def.a)
      pad(s, def.s)
      local changed = clampArray(p, P_RANGE)
      changed = clampArray(a, A_RANGE) or changed
      bat[#bat + 1] = { p = p, a = a, s = s }
      if #bat ~= k or changed then
        compacted = true
      end
    end
  end
  if compacted then
    for k = 1, 4 do
      if bat[k] then
        saveBattery(k)
      else
        clearSlot(k)
      end
    end
  end
  if cfg.smallB < 1 or cfg.smallB > math.max(1, #bat) then
    saveApp("smallB", 1)
  end
  if cfg.cfgV ~= 1 then
    saveApp("cfgV", 1)
  end
end

------------------------------------------------------------------------------
-- Derived values: recomputed only when a setting changes, never per tick.
------------------------------------------------------------------------------

local dv = {}               -- dv[k]: derived values of battery k

-- Label width in FONT_MINI from MINI_W (R6); lcd isn't available in form
-- callbacks, so the form measures with this table.
local function labelWidth(text)
  local w = 0
  for i = 1, #text do
    w = w + (MINI_W[string.sub(text, i, i)] or MINI_W_OTHER)
  end
  return math.ceil(w + MINI_W_EXTRA * #text)
end

local function labelFits(text)
  return labelWidth(text) <= L.slotW - 2
end

-- FR-003: category label (or its short form when it wouldn't fit), or the
-- custom name, plus "-n" when the category is used more than once.
local function makeLabel(b)
  local c = catOf(b.p[P.CAT])
  local base = c.label
  if b.p[P.CAT] == CUSTOM or not CAT[b.p[P.CAT]] then
    base = b.s[S.NAME]
    if base == "" then
      base = "BAT"
    end
  end
  local num = b.p[P.NUM]
  local text = base
  if num > 0 then
    text = base .. "-" .. num
  end
  if not labelFits(text) and c.short then
    text = c.short
    if num > 0 then
      text = text .. "-" .. num
    end
  end
  return text
end

local function recompute(k)
  local b = bat[k]
  local p, a = b.p, b.a
  local d = dv[k] or {}
  dv[k] = d
  d.label = makeLabel(b)
  d.cat = catOf(p[P.CAT])
  d.mode = p[P.CAPMODE]
  if p[P.CAPID] == 0 then
    d.mode = M.NONE
  end
  -- No capacity sensor, or an mAh source without the pack's capacity: the
  -- voltage sensor gives the % (FR-004).
  d.noMah = (d.mode == M.MAH or d.mode == M.AH) and p[P.MAH] <= 0
  d.capFromV = p[P.VID] ~= 0 and (d.mode == M.NONE or d.noMah)
  if d.capFromV then
    d.mode = M.VOLT
  end
  -- Which reading is the battery's voltage: its own sensor, else the
  -- capacity source when that is a voltage (data-model "voltOf").
  d.voltSrc = 0
  if p[P.VID] ~= 0 then
    d.voltSrc = 1
  elseif d.mode == M.VOLT then
    d.voltSrc = 2
  end
  d.hasV = d.voltSrc ~= 0
  d.hasI = p[P.IID] ~= 0
  d.iScale = (p[P.EDITED] & E.MA) ~= 0 and 0.001 or 1
  d.lowest = 0
  for i = 4, 1, -1 do
    if (a[A.LVLON] & (1 << (i - 1))) ~= 0 then
      d.lowest = i
      break
    end
  end
  d.lvThrCell = a[A.LVTHR]
  if a[A.LVMODE] == 2 then
    d.lvThrCell = a[A.LVTHR] / p[P.CELLS]
  end
  d.iOn = a[A.ITHR] > 0 and a[A.IDLY] > 0 and a[A.IRPT] > 0
  d.chem = CHEM[p[P.CHEM]]
end

local function recomputeAll()
  for k = 1, #bat do
    recompute(k)
  end
end

------------------------------------------------------------------------------
-- Session state (not persisted; rebuilt by init on every model load).
------------------------------------------------------------------------------

local TEL = { NONE = 0, LIVE = 1, LOST = 2 }
local K = { LV = 1, CUR = 2, LVL = 3, NP = 4, MAX = 5, N = 5 }   -- callout kinds, FR-034a order

local ss = {}               -- ss[k]: session state of battery k (data-model.md)
local app = {
  fastT = 0, slowT = 0, playing = false, cpuWorst = 0,
  voiceOk = false, useAppVoice = false, gaugeOk = false,
  hintBlank = false,          -- flash phase of the missing-capacity hint
}

local function newSession()
  local s = {
    tel = TEL.NONE, badSince = nil,
    capVal = nil, capOk = false,
    pct = 0, pctLast = 0, vPct = nil, vPctLast = nil,
    -- mAh counting: % at the session start, the counter then, its last reading
    start = 100, used0 = 0, usedPrev = 0, raw = 100, waitT = nil,
    vSum = 0, vN = 0, vNow = nil, vEst = nil,
    iNow = nil, band = 1,
    fired = 0, rptOn = false, rptN = 0, rptT = 0,
    vLast = nil, lvBelowT = nil, lvAboveT = nil, lvOn = false, lvN = 0, lvT = 0,
    iAboveT = nil, iAlarm = false, iRptT = 0,
    peak = peak.new(), riseT = 0, lastAnn = 0,
    npDueT = nil, npDone = true,
    pend = {}, pendV = {}, spokeT = 0,
    -- cached display strings and the values they were built from
    txtPct = TXT.dash, txtSmall = "", txtLine = "", shownPct = -1, shownV = -1, shownI = -1,
  }
  for i = 1, K.N do
    s.pend[i], s.pendV[i] = false, 0
  end
  return s
end

local function resetSessions()
  ss = {}
  for k = 1, #bat do
    ss[k] = newSession()
  end
end

------------------------------------------------------------------------------
-- Capacity maths (FR-004, R1, R3)
------------------------------------------------------------------------------

-- % from resting voltage per cell (cV), clamped 0..100; at or below Cutoff
-- it is 0 (R3).
local function curvePct(chem, vCell, cut)
  if vCell <= cut then
    return 0
  end
  local c = CURVE[chem]
  if vCell >= c[1] then
    return 100
  end
  for i = 1, 10 do
    local hi, lo = c[i], c[i + 1]
    if vCell > lo then
      return 100 - 10 * (i - 1) - 10 * (hi - vCell) / (hi - lo)
    end
  end
  return 0
end

-- Raw % from a % or voltage source's last reading in capacity mode `mode`
-- (mAh sources are counted in updateCapacity); nil for other modes.
local function rawPct(k, value, mode)
  local b = bat[k]
  if mode == M.PCT then
    return value
  elseif mode == M.VOLT then
    return curvePct(b.p[P.CHEM], value * 100 / b.p[P.CELLS], b.p[P.VCUT])
  end
  return nil
end

local function roundPct(x)
  return clamp(math.floor(x + 0.5), 0, 100)
end

-- Colour band: "below" is strict (data-model.md).
local function bandOf(b, pct)
  local p = b.p
  if pct < p[P.BANDR] then
    return 4
  elseif pct < p[P.BANDO] then
    return 3
  elseif pct < p[P.BANDY] then
    return 2
  end
  return 1
end

------------------------------------------------------------------------------
-- SIM (debug, R13): scripted profiles in place of battery 1's sensors,
-- chosen in the settings form while SIM is true. Each profile is a list of
-- { ms from selection, % remaining, volts per cell (cV), amps }, linearly
-- interpolated; % -1 means invalid data. The last point holds after the end.
------------------------------------------------------------------------------

local sim = {
  idx = 1, t0 = 0,
  names = { "Off", "1 Discharge", "2 Noisy voltage", "3 Jittery discharge", "4 Voltage sags",
    "5 Start at 35%", "6 Current spikes", "7 Steady 40 A", "8 Start at 82%", "9 Start at 95%",
    "10 Swap to fuller pack", "11 Brown-out" },
  -- volts +-3 %
  noise = { false, false, true, false, false, false, false, false, false, false, false, false },
  -- % +-2 points
  jitter = { false, false, false, true, false, false, false, false, false, false, false, false },
  prof = {
    {},
    { { 0, 100, 415, 5 }, { 150000, 0, 350, 5 } },   -- 100 -> 0 % in 2.5 min
    { { 0, 90, 334, 0 }, { 120000, 50, 329, 0 }, { 240000, 10, 315, 0 } },
    -- through 60/50/40/30 in 4 minutes, % jittering around each level
    { { 0, 70, 390, 0 }, { 240000, 20, 373, 0 } },
    -- 3.80 V/cell; sag to 3.55 for 1.5 s (no alarm), then for 3 s (alarm)
    { { 0, 60, 380, 0 }, { 5000, 60, 380, 0 }, { 5001, 60, 355, 0 }, { 6500, 60, 355, 0 },
      { 6501, 60, 380, 0 }, { 12000, 60, 380, 0 }, { 12001, 60, 355, 0 }, { 15000, 60, 355, 0 },
      { 15001, 60, 380, 0 } },
    { { 0, 35, 377, 0 } },
    -- climb to 40 A and hold; a one-sample 150 A spike at 10 s (shorter
    -- than the 200 ms read tick); climb to 92 A, hold 3 s, cruise at 50 A
    { { 0, 90, 385, 10 }, { 5000, 89, 384, 40 }, { 10000, 88, 383, 40 }, { 10001, 88, 383, 150 },
      { 10199, 88, 383, 150 }, { 10200, 88, 383, 40 }, { 15000, 86, 382, 60 },
      { 18000, 85, 381, 92 }, { 21000, 85, 381, 92 }, { 21001, 85, 381, 50 }, { 30000, 83, 380, 50 } },
    { { 0, 80, 380, 40 } },
    -- New-pack check (FR-029); voltages are LiPo resting values for that %.
    { { 0, 82, 404, 0 } },
    { { 0, 95, 416, 0 } },
    -- 40 %, telemetry off for 3 s, back at 75 %: a new pack
    { { 0, 40, 380, 0 }, { 10000, 40, 380, 0 }, { 10001, -1, 380, 0 }, { 13000, -1, 380, 0 },
      { 13001, 75, 398, 0 } },
    -- 50 %, telemetry off for 3 s, back at 50 %: a brown-out
    { { 0, 50, 384, 0 }, { 10000, 50, 384, 0 }, { 10001, -1, 384, 0 }, { 13000, -1, 384, 0 },
      { 13001, 50, 384, 0 } },
  },
}

-- Returns the profile's %, cV per cell and amps at `now`, or nil when the
-- profile says "invalid".
local function simPoint(now)
  local prof = sim.prof[sim.idx]
  local t = now - sim.t0
  local a = prof[1]
  for i = 2, #prof do
    local b = prof[i]
    if t < b[1] then
      local f = (t - a[1]) / (b[1] - a[1])
      if a[2] < 0 then
        return nil
      end
      return a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f, a[4] + (b[4] - a[4]) * f
    end
    a = b
  end
  if a[2] < 0 then
    return nil
  end
  return a[2], a[3], a[4]
end

-- Battery 1's three readings from the profile, in each sensor's own units.
local function simRead(now)
  local pct, vCell, amps = simPoint(now)
  if pct == nil then
    return nil, nil, nil
  end
  local b, d = bat[1], dv[1]
  local volts = vCell * b.p[P.CELLS] / 100
  if sim.noise[sim.idx] then
    volts = volts * (0.97 + 0.06 * math.random())
  end
  if sim.jitter[sim.idx] then
    pct = clamp(pct - 2 + 4 * math.random(), 0, 100)
  end
  local cap = pct
  if d.mode == M.MAH then
    cap = b.p[P.MAH] * (100 - pct) / 100
  elseif d.mode == M.AH then
    cap = b.p[P.MAH] * (100 - pct) / 100000
  elseif d.mode == M.VOLT then
    cap = volts
  end
  return cap, volts, amps
end

-- Capacity mode in use. A SIM profile also drives battery 1 when it has no
-- capacity sensor (e.g. on a transmitter without one), as a % source.
local function modeOf(k)
  local mode = dv[k].mode
  if SIM and k == 1 and sim.idx > 1 and mode == M.NONE then
    return M.PCT
  end
  return mode
end

------------------------------------------------------------------------------
-- Callout scheduler (R9, contracts/audio-events.md). Pending flags per
-- battery and kind; nothing queues twice; one phrase per dispatch, only
-- while nothing is playing (FR-034, FR-034a).
------------------------------------------------------------------------------

local function raise(k, kind, value)
  local s = ss[k]
  s.pend[kind], s.pendV[kind] = true, value
end

local function clearPending(k)
  local s = ss[k]
  for i = 1, K.N do
    s.pend[i] = false
  end
end

-- Transmitter voice (FR-033): the battery's voice-name file, if picked,
-- then the number and unit. US6 adds the app voice in front of this.
local function speakTransmitter(k, kind, value)
  local b = bat[k]
  if b.s[S.VOICE] ~= "" then
    system.playFile(b.s[S.VOICE], AUDIO_QUEUE)
  end
  if kind == K.LV then
    if b.a[A.LVMODE] == 2 then
      system.playNumber(math.floor(value / 10 + 0.5) / 10, 1, "V")
    else
      system.playNumber(math.floor(value + 0.5) / 100, 2, "V")
    end
  elseif kind == K.CUR or kind == K.MAX then
    system.playNumber(value, 0, "A")
  else
    system.playNumber(value, 0, "%")
  end
end

-- App voice (FR-030 - FR-033, research R8/R9): Piper "Amy" files made by
-- tools/voice/make_batcap.py. Checked once in init(); a phrase is never
-- half app voice.
local VOICE = {
  dir = "/Apps/AG-BatCp/voice/",
  words = { "pct", "amps", "volts", "vpc", "point", "max", "hicur", "lowv", "notfull",
    "n_flt", "n_rx", "n_ecu", "n_gear", "n_brk", "n_lgt", "n_aux", "n_bat" },
  maxNum = 500,
}
local KIND_WORD = { [K.LV] = "lowv", [K.CUR] = "hicur", [K.NP] = "notfull", [K.MAX] = "max" }
local phrase = {}           -- file stems of the phrase being built, reused

-- Jeti's io is function-style (constitution III). The transmitter opens
-- "/Apps/..."; the JETI Studio emulator only opens it without the leading
-- "/" (API notes, 2026-10-05). Playback keeps the absolute path.
local function fileExists(path)
  local f = io.open(path, "r") or io.open(string.sub(path, 2), "r")
  if f then
    io.close(f)
    return true
  end
  return false
end

local function checkVoice()
  local ok = fileExists(VOICE.dir .. "0.wav") and fileExists(VOICE.dir .. VOICE.maxNum .. ".wav")
  for _, w in ipairs(VOICE.words) do
    ok = ok and fileExists(VOICE.dir .. w .. ".wav")
  end
  app.voiceOk = ok
  app.useAppVoice = ok and cfg.voice ~= 2
end

local function add(stem)
  phrase[#phrase + 1] = stem
end

-- Adds number n as a file; false when it can't be spoken in the app voice
-- (over 500, or its file is missing: FR-033).
local function addNumber(n)
  if n < 0 or n > VOICE.maxNum or not fileExists(VOICE.dir .. n .. ".wav") then
    return false
  end
  add(tostring(n))
  return true
end

-- "receiver 2, 30 percent", "flight, low voltage, 3 point 5 8 volts per
-- cell" (contracts/audio-events.md). Returns false to fall back.
local function buildPhrase(k, kind, value)
  for i = #phrase, 1, -1 do
    phrase[i] = nil
  end
  local b = bat[k]
  add(dv[k].cat.voice)
  if b.p[P.NUM] > 0 and not addNumber(b.p[P.NUM]) then
    return false
  end
  if KIND_WORD[kind] then
    add(KIND_WORD[kind])
  end
  local unit
  if kind == K.LV then
    local whole, digits
    if b.a[A.LVMODE] == 2 then
      local tenths = math.floor(value / 10 + 0.5)
      whole, digits, unit = tenths // 10, { tenths % 10 }, "volts"
    else
      local cv = math.floor(value + 0.5)
      whole, digits, unit = cv // 100, { (cv // 10) % 10, cv % 10 }, "vpc"
    end
    if not addNumber(whole) then
      return false
    end
    add("point")
    for _, dgt in ipairs(digits) do
      if not addNumber(dgt) then
        return false
      end
    end
  else
    if not addNumber(math.floor(value + 0.5)) then
      return false
    end
    unit = (kind == K.CUR or kind == K.MAX) and "amps" or "pct"
  end
  if cfg.numOnly ~= 1 then
    add(unit)
  end
  return true
end

local function speak(k, kind, value)
  if app.useAppVoice and buildPhrase(k, kind, value) then
    for _, stem in ipairs(phrase) do
      system.playFile(VOICE.dir .. stem .. ".wav", AUDIO_QUEUE)
    end
    return
  end
  speakTransmitter(k, kind, value)
end

-- Repeat bookkeeping once a phrase has started (start to start, FR-018,
-- FR-021): the lowest capacity level and the low-voltage alarm count their
-- plays against the battery's max count.
local function onSpoken(k, kind, value, now)
  local s, a, d = ss[k], bat[k].a, dv[k]
  if kind == K.LVL and d.lowest > 0 and value == a[d.lowest] then
    s.rptT, s.rptN = now, s.rptN + 1
    if a[A.MAXCNT] > 0 and s.rptN >= a[A.MAXCNT] then
      s.rptOn = false
    end
  elseif kind == K.LV then
    s.lvT, s.lvN = now, s.lvN + 1
  elseif kind == K.CUR then
    s.iRptT = now
  elseif kind == K.MAX then
    s.lastAnn = value
  end
end

local function dispatch(now)
  if system.isPlayback() then
    return
  end
  for kind = 1, K.N do
    for k = 1, #bat do
      local s = ss[k]
      if s.pend[kind] then
        s.pend[kind] = false
        speak(k, kind, s.pendV[kind])
        s.spokeT = now
        onSpoken(k, kind, s.pendV[kind], now)
        return
      end
    end
  end
end

------------------------------------------------------------------------------
-- Telemetry: reading, tracking, new pack (R1, R2, R4)
------------------------------------------------------------------------------

-- A new pack session (app start counts as one): resets this battery's
-- callout, alarm and max state (R4).
local function startPackSession(k, now, pct)
  local s = ss[k]
  s.pct, s.vEst = pct, nil
  s.fired, s.rptOn, s.rptN, s.rptT = 0, false, 0, 0
  s.lvBelowT, s.lvAboveT, s.lvOn, s.lvN, s.lvT = nil, nil, false, 0, 0
  s.iAboveT, s.iAlarm = nil, false
  peak.reset(s.peak)
  s.riseT, s.lastAnn = 0, 0
  s.npDueT, s.npDone = now + T.NP_DELAY, false
  clearPending(k)
end

-- Fast tick: read each assigned sensor once (always through system, R3 of
-- Speed Gauge: the emulator's telemetry app replaces these functions).
local txTel = nil            -- getTxTelemetry() for this tick, read on first use

-- One reading, or nil when invalid. A receiver's voltage is valid only
-- while its signal quality is above 0 (transmitter, 2026-11-05).
local function readValue(id, par)
  if id == RXV then
    if txTel == nil then
      txTel = system.getTxTelemetry()
    end
    local v, q = txTel[RXV_FIELD[par]], txTel[RXV_Q[par]]
    if v ~= nil and v > 0 and q ~= nil and q > 0 then
      return v
    end
    return nil
  end
  local v = system.getSensorValueByID(id, par)
  if v ~= nil and v.valid then
    return v.value
  end
  return nil
end

local function readSensors(now)
  txTel = nil
  for k = 1, #bat do
    local b, d, s = bat[k], dv[k], ss[k]
    local p = b.p
    local cap, volts, amps
    local simOn = SIM and k == 1 and sim.idx > 1
    if simOn then
      cap, volts, amps = simRead(now)
      if d.voltSrc == 0 then
        volts = nil
      end
      if not d.hasI then
        amps = nil
      end
    else
      if p[P.CAPID] ~= 0 and not d.capFromV then
        cap = readValue(p[P.CAPID], p[P.CAPPAR])
      end
      if d.voltSrc == 1 then
        volts = readValue(p[P.VID], p[P.VPAR])
        if d.capFromV then
          cap = volts
        end
      elseif d.voltSrc == 2 then
        volts = cap
      end
      if d.hasI then
        amps = readValue(p[P.IID], p[P.IPAR])
        if amps ~= nil then
          amps = amps * d.iScale
        end
      end
    end
    if cap ~= nil then
      s.capVal, s.capOk, s.badSince = cap, true, nil
    else
      s.capOk = false
      if s.badSince == nil then
        s.badSince = now
      end
    end
    if volts ~= nil then
      s.vSum, s.vN = s.vSum + volts * 100, s.vN + 1
      s.vLast = volts * 100
    else
      s.vLast = nil
    end
    s.iNow = amps
  end
end

-- Slow tick, per battery: voltage average, telemetry state, new pack or
-- brown-out (data-model "Telemetry"), % remaining and band.
local function updateCapacity(k, now)
  local b, d, s = bat[k], dv[k], ss[k]
  -- 1 s voltage average (cV, pack) and its unsmoothed curve estimate.
  if s.vN > 0 then
    s.vNow = s.vSum / s.vN
    s.vPct = curvePct(b.p[P.CHEM], s.vNow / b.p[P.CELLS], b.p[P.VCUT])
  else
    s.vNow, s.vPct = nil, nil
  end
  s.vSum, s.vN = 0, 0

  local mode = modeOf(k)
  if mode == M.NONE then
    s.tel = TEL.NONE
    return
  end
  if s.tel == TEL.LIVE and not s.capOk and s.badSince and now - s.badSince >= T.LOST then
    s.tel = TEL.LOST
    s.pctLast, s.vPctLast = s.pct, s.vPct
    clearPending(k)
    return
  end
  if not s.capOk then
    return                    -- short gap or still lost: hold the last value
  end
  -- An mAh counter needn't start at 0 (a CB 210 keeps its count across
  -- power-ups, field test 2026-11-08): the pack starts at its resting-voltage
  -- %, or 100 without a voltage sensor, and loses what is counted from then.
  local counted = mode == M.MAH or mode == M.AH
  local used, raw = 0, nil
  if counted then
    if b.p[P.MAH] <= 0 then
      return
    end
    used = s.capVal
    if mode == M.AH then
      used = used * 1000
    end
  else
    raw = rawPct(k, s.capVal, mode)
    if raw == nil then
      return
    end
  end
  if s.tel == TEL.NONE then
    if counted then
      if d.hasV and s.vPct == nil then
        s.waitT = s.waitT or now
        if now - s.waitT < T.VWAIT then
          return
        end
      end
      s.start, s.used0, s.usedPrev = s.vPct or 100, used, used
    end
    s.tel = TEL.LIVE
    startPackSession(k, now, roundPct(counted and s.start or raw))
  elseif s.tel == TEL.LOST then
    s.tel = TEL.LIVE
    -- New pack: 20 points higher, and with a separate voltage sensor the
    -- voltage estimate agrees (R4). Otherwise a brown-out: keep everything.
    -- A counted pack goes by its voltage, else by its counter going back.
    local isNew
    if counted then
      if s.vPct ~= nil and s.vPctLast ~= nil then
        isNew = s.vPct >= s.vPctLast + T.NEWPACK
      else
        isNew = used < s.usedPrev
      end
    else
      isNew = raw >= s.pctLast + T.NEWPACK
      if isNew and d.voltSrc == 1 and s.vPct ~= nil and s.vPctLast ~= nil then
        isNew = s.vPct >= s.vPctLast + T.NEWPACK
      end
    end
    if isNew then
      if counted then
        s.start, s.used0, s.usedPrev = s.vPct or 100, used, used
      end
      startPackSession(k, now, roundPct(counted and s.start or raw))
    end
  end
  if counted then
    -- A counter that goes back (reset by its sensor) counts on from here.
    if used < s.usedPrev then
      s.start, s.used0 = s.raw, used
    end
    s.usedPrev = used
    raw = s.start - (used - s.used0) * 100 / b.p[P.MAH]
    s.raw = raw
  end
  -- Voltage source: smoothed (10 s time constant), held under load (R3).
  if mode == M.VOLT then
    local loaded = s.iNow ~= nil and s.iNow > math.max(1, b.p[P.MAH] / 10000)
    if s.vEst == nil then
      s.vEst = raw
    elseif not loaded then
      s.vEst = s.vEst + 0.1 * (raw - s.vEst)
    end
    raw = s.vEst
  end
  s.pct = roundPct(raw)
  s.band = bandOf(b, s.pct)
end

------------------------------------------------------------------------------
-- Capacity callouts (FR-016 - FR-018, data-model "Capacity level k")
------------------------------------------------------------------------------

local function levelOn(a, i)
  return (a[A.LVLON] & (1 << (i - 1))) ~= 0
end

-- Marks every enabled, armed level the current % has reached as fired and
-- returns the lowest of them (slots are strictly descending, so the last
-- one), or nil.
local function markCrossed(k)
  local a, s = bat[k].a, ss[k]
  local hit = nil
  for i = 1, 4 do
    local bit = 1 << (i - 1)
    if levelOn(a, i) and (s.fired & bit) == 0 and s.pct <= a[A.LVL1 + i - 1] then
      s.fired = s.fired | bit
      hit = i
    end
  end
  return hit
end

-- After the levels are edited (or one is turned off): re-arm from the
-- current %, silently (spec edge cases). The lowest keeps repeating only if
-- it was repeating and the new lowest has already fired.
local function rearmLevels(k)
  local s, d = ss[k], dv[k]
  s.fired = 0
  markCrossed(k)
  s.rptOn = s.rptOn and d.lowest > 0 and (s.fired & (1 << (d.lowest - 1))) ~= 0
end

-- Slow tick, LIVE batteries. A level fires at or below its value and
-- re-arms HYST points above it; when several fire at once only the lowest
-- speaks (also at the start of a pack session, US2 #4). The lowest enabled
-- level then repeats every rptS, start to start, up to maxCnt plays.
local function updateLevels(k, now)
  local a, d, s = bat[k].a, dv[k], ss[k]
  for i = 1, 4 do
    local bit = 1 << (i - 1)
    if (s.fired & bit) ~= 0 and s.pct >= a[A.LVL1 + i - 1] + T.HYST then
      s.fired = s.fired & ~bit
      if i == d.lowest then
        s.rptOn = false
      end
    end
  end
  local hit = markCrossed(k)
  if hit then
    raise(k, K.LVL, a[A.LVL1 + hit - 1])
    if hit == d.lowest then
      s.rptOn, s.rptN, s.rptT = true, 0, 0
    end
  elseif s.rptOn and s.rptT > 0 and not s.pend[K.LVL]
      and now - s.rptT >= a[A.RPT] * 1000 then
    if a[A.MAXCNT] == 0 or s.rptN < a[A.MAXCNT] then
      raise(k, K.LVL, a[A.LVL1 + d.lowest - 1])
    else
      s.rptOn = false
    end
  end
end

------------------------------------------------------------------------------
-- Low-voltage alarm (FR-019 - FR-022, data-model "Low-voltage alarm").
-- Fast tick, on the latest voltage reading, compared per cell.
------------------------------------------------------------------------------

local function updateLowVoltage(k, now)
  local a, d, s, p = bat[k].a, dv[k], ss[k], bat[k].p
  if not d.hasV or a[A.LVMODE] == 0 or s.tel ~= TEL.LIVE or s.vLast == nil then
    s.lvBelowT, s.lvAboveT = nil, nil
    return
  end
  local vCell = s.vLast / p[P.CELLS]
  local thr = d.lvThrCell
  local dly = a[A.LVDLY] * 100
  -- Value to speak: volts per cell, or pack volts, in cV (FR-021).
  local value = a[A.LVMODE] == 2 and s.vLast or vCell
  if vCell < thr then
    s.lvAboveT = nil
    if s.lvBelowT == nil then
      s.lvBelowT = now
    end
    if not s.lvOn and now - s.lvBelowT >= dly then
      s.lvOn, s.lvN, s.lvT = true, 0, 0
      raise(k, K.LV, value)
    end
  else
    s.lvBelowT = nil
    -- Clears only after recovering 0.05 V per cell for the delay (FR-020).
    if s.lvOn and vCell >= thr + 5 then
      if s.lvAboveT == nil then
        s.lvAboveT = now
      end
      if now - s.lvAboveT >= dly then
        s.lvOn, s.lvAboveT = false, nil
        s.pend[K.LV] = false
      end
    else
      s.lvAboveT = nil
    end
  end
  if s.lvOn then
    if s.pend[K.LV] then
      s.pendV[K.LV] = value   -- speak the latest reading
    elseif s.lvT > 0 and now - s.lvT >= a[A.RPT] * 1000
        and (a[A.MAXCNT] == 0 or s.lvN < a[A.MAXCNT]) then
      raise(k, K.LV, value)
    end
  end
end

------------------------------------------------------------------------------
-- Current alarm and max current (FR-024 - FR-027, data-model "Current
-- alarm", "Max current"). Fast tick, LIVE batteries with a current reading.
------------------------------------------------------------------------------

local function updateCurrent(k, now)
  local a, d, s = bat[k].a, dv[k], ss[k]
  local i = s.iNow
  if not d.hasI or s.tel ~= TEL.LIVE or i == nil then
    s.iAboveT = nil
    return
  end
  -- Max: Speed Gauge's spike filter (R7). riseT = when it last rose.
  local _, rose = peak.update(s.peak, i, now)
  if rose then
    s.riseT = now
  end
  -- Alarm: above the threshold for the delay, repeat while above.
  if not d.iOn then
    s.iAboveT, s.iAlarm = nil, false
    return
  end
  local n = math.floor(i + 0.5)
  if i > a[A.ITHR] then
    if s.iAboveT == nil then
      s.iAboveT = now
    end
    if not s.iAlarm and now - s.iAboveT >= a[A.IDLY] * 100 then
      s.iAlarm, s.iRptT = true, 0
      raise(k, K.CUR, n)
    elseif s.iAlarm then
      if s.pend[K.CUR] then
        s.pendV[K.CUR] = n    -- speak the latest reading
      elseif s.iRptT > 0 and now - s.iRptT >= a[A.IRPT] * 1000 then
        raise(k, K.CUR, n)
      end
    end
  else
    s.iAboveT, s.iAlarm = nil, false
    s.pend[K.CUR] = false
  end
end

-- Slow tick: a new max is spoken once it hasn't risen for 1 s and beats the
-- last announced max by the sensitivity (FR-026). A waiting callout is
-- replaced by the newer value (FR-034a).
local function updateMax(k, now)
  local a, d, s = bat[k].a, dv[k], ss[k]
  if not d.hasI or a[A.MAXON] ~= 1 or s.tel ~= TEL.LIVE then
    return
  end
  local maxNow = s.peak.max
  if maxNow > 0 and now - s.riseT >= 1000 and maxNow - s.lastAnn >= a[A.MAXSENS] then
    raise(k, K.MAX, math.floor(maxNow + 0.5))
  end
end

-- New-pack check (FR-029): 3 s after a pack session starts, the resting
-- voltage estimate (unsmoothed 1 s average, R3) below the threshold says
-- "pack not full" once. Only a new pack schedules it again (a brown-out
-- keeps npDone, R4). Waits while no voltage reading arrives.
local function updatePackCheck(k, now)
  local a, d, s = bat[k].a, dv[k], ss[k]
  if s.npDone or a[A.NPON] ~= 1 or not d.hasV or s.npDueT == nil or now < s.npDueT then
    return
  end
  if s.vPct == nil then
    return
  end
  s.npDone = true
  local pct = roundPct(s.vPct)
  if pct < a[A.NPTHR] then
    raise(k, K.NP, pct)
  end
end

local function resetMax(k)
  local s = ss[k]
  peak.reset(s.peak)
  s.riseT, s.lastAnn = 0, 0
  s.pend[K.MAX] = false
end

-- Cached strings for the windows, rebuilt only when their value changed.
local function updateStrings(k)
  local d, s = dv[k], ss[k]
  local shown = -1
  if s.tel == TEL.LIVE then
    shown = s.pct
  end
  if shown ~= s.shownPct then
    s.shownPct = shown
    s.txtPct = shown >= 0 and (shown .. "%") or TXT.dash
  end
  -- Small window values line: "8.1V 0.4A", each part only when assigned,
  -- "--" for a lost reading (contracts/telemetry-window.md).
  local v, i = -1, -1
  if d.hasV then
    v = -2
    if s.vNow then
      v = math.floor(s.vNow / 10 + 0.5)          -- tenths of a volt
    end
  end
  if d.hasI then
    i = -2
    if s.iNow then
      i = math.floor(s.iNow * 10 + 0.5)          -- tenths of an amp
    end
  end
  if v ~= s.shownV or i ~= s.shownI then
    s.shownV, s.shownI = v, i
    local text = ""
    if v == -2 then
      text = "--V"
    elseif v >= 0 then
      text = string.format("%.1fV", v / 10)
    end
    if i ~= -1 then
      if text ~= "" then
        text = text .. " "
      end
      text = text .. (i == -2 and "--A" or string.format("%.1fA", i / 10))
    end
    s.txtSmall = text
    -- Double window line (FR-011): current when a current sensor is
    -- assigned ("--" when lost), else pack voltage, else blank.
    if i ~= -1 then
      s.txtLine = i == -2 and TXT.dash or string.format("%.1f A", i / 10)
    elseif v ~= -1 then
      s.txtLine = v == -2 and TXT.dash or string.format("%.1f V", v / 10)
    else
      s.txtLine = ""
    end
  end
end

------------------------------------------------------------------------------
-- Settings form (contracts/settings-form.md). One subform, rebuilt with
-- form.reinit(1) and drawn from `cur` (0 = main page, k = battery k):
-- reinit(2) appeared to close the form in the emulator (Throttle Setup
-- Wizard, 2026-10-10).
------------------------------------------------------------------------------

local cur = 0
local formOpen = false      -- loop may touch form rows only while true
local idx = {}              -- component indices of rows updated after creation
local keepRow = nil         -- focused row to restore after a rebuild
local note = { short = false, band = false, title = false, levels = false }   -- one-off notes for this form session
local LABEL_W = 180

-- Sensor lists for the open battery screen (R1): one getSensors() pass.
local lists = {}

local function goTo(screen, keep)
  cur = screen
  keepRow = keep and form.getFocusedRow() or nil
  form.reinit(1)
end

local function refresh()
  goTo(cur, true)
end

local function heading(text)
  form.addRow(1)
  form.addLabel({ label = text, font = FONT_BOLD })
end

local function hint(text, visible)
  form.addRow(1)
  return form.addLabel({ label = text, font = FONT_MINI, visible = visible ~= false })
end

local function newList()
  return { labels = { "(none)" }, ids = { 0 }, pars = { 0 }, units = { "" }, sel = 1, nf = 0 }
end

local function addEntry(list, label, s)
  local n = #list.labels + 1
  list.labels[n], list.ids[n], list.pars[n], list.units[n] = label, s.id, s.param, s.unit or ""
end

-- Selects the saved sensor, or adds "<label> (not found)" (Speed Gauge R4).
local function selectSaved(list, id, par, lbl)
  if id == 0 then
    return
  end
  for i = 2, #list.labels do
    if list.ids[i] == id and list.pars[i] == par then
      list.sel = i
      return
    end
  end
  local n = #list.labels + 1
  list.labels[n], list.ids[n], list.pars[n], list.units[n] = lbl .. " (not found)", id, par, ""
  list.sel, list.nf = n, n
end

local function buildLists(k)
  local p, s = bat[k].p, bat[k].s
  lists = { cap = newList(), volt = newList(), cur = newList() }
  for i = 1, 3 do
    local e = { id = RXV, param = i, unit = "V" }
    addEntry(lists.cap, RXV_LABEL[i], e)
    addEntry(lists.volt, RXV_LABEL[i], e)
  end
  local parent = ""
  for _, e in ipairs(system.getSensors()) do
    if e.param == 0 then
      parent = e.label
    elseif e.type ~= 5 and e.type ~= 9 then
      local u = e.unit or ""
      local label = (parent ~= "") and (parent .. " / " .. e.label) or e.label
      if CAP_UNITS[u] then
        addEntry(lists.cap, label, e)
      end
      if u == "V" then
        addEntry(lists.volt, label, e)
      end
      if u == "A" or u == "mA" then
        addEntry(lists.cur, label, e)
      end
    end
  end
  selectSaved(lists.cap, p[P.CAPID], p[P.CAPPAR], s[S.CAPLBL])
  selectSaved(lists.volt, p[P.VID], p[P.VPAR], s[S.VLBL])
  selectSaved(lists.cur, p[P.IID], p[P.IPAR], s[S.ILBL])
end

-- Label numbering (FR-003): a second battery in a category numbers the
-- first "-1" and itself the next free number; deleting one doesn't
-- renumber the rest (spec edge case).
local function assignNumber(k)
  local cat = bat[k].p[P.CAT]
  local maxNum, others = 0, {}
  for j = 1, #bat do
    if j ~= k and bat[j].p[P.CAT] == cat then
      others[#others + 1] = j
      maxNum = math.max(maxNum, bat[j].p[P.NUM])
    end
  end
  if #others == 0 then
    bat[k].p[P.NUM] = 0
    return
  end
  if maxNum == 0 then
    bat[others[1]].p[P.NUM] = 1
    saveBattery(others[1])
    recompute(others[1])
    maxNum = 1
  end
  bat[k].p[P.NUM] = maxNum + 1
end

-- FR-008: refill a group of defaults; if any of them was edited, ask first.
-- `groups` is an edited-mask of the groups this change would refill.
local function askOverwrite(b, groups)
  if (b.p[P.EDITED] & groups) == 0 then
    return true
  end
  return form.question("Overwrite edited values?", "Yes: use the new defaults.",
    "No: keep your edits, update the rest.", 0, false, 0) == 1
end

local function refill(k, groups)
  local b = bat[k]
  local p, a = b.p, b.a
  local c = catOf(p[P.CAT])
  local all = askOverwrite(b, groups)
  local function take(bit)
    return (groups & bit) ~= 0 and (all or (p[P.EDITED] & bit) == 0)
  end
  if take(E.VOLT) then
    fillVoltages(p)
    p[P.EDITED] = p[P.EDITED] & ~E.VOLT
  end
  if take(E.BAND) then
    fillBands(p, c)
    p[P.EDITED] = p[P.EDITED] & ~E.BAND
  end
  if take(E.LVL) then
    fillLevels(a, c)
    p[P.EDITED] = p[P.EDITED] & ~E.LVL
  end
  if take(E.LVTHR) then
    a[A.LVTHR] = defaultLvThr(b)
    p[P.EDITED] = p[P.EDITED] & ~E.LVTHR
  end
end

local function setCategory(k, cat)
  local b = bat[k]
  local p = b.p
  if p[P.CAT] == cat then
    return
  end
  local oldCat = p[P.CAT]
  p[P.CAT] = cat
  assignNumber(k)
  -- Moving out of a category that then has one battery left drops that
  -- one's number again ("RX-1" -> "RX"), e.g. after "Add battery" briefly
  -- made a second Receiver. Deleting never renumbers (spec edge case).
  local left = nil
  for j = 1, #bat do
    if bat[j].p[P.CAT] == oldCat then
      if left then
        left = 0
        break
      end
      left = j
    end
  end
  if left and left > 0 and bat[left].p[P.NUM] ~= 0 then
    bat[left].p[P.NUM] = 0
    recompute(left)
    saveBattery(left)
  end
  local c = catOf(cat)
  b.a[A.MAXON] = c.maxOn
  local groups = E.BAND | E.LVL
  if c.chem ~= p[P.CHEM] then
    p[P.CHEM] = c.chem
    groups = groups | E.VOLT | E.LVTHR
  end
  refill(k, groups)
  recompute(k)
  saveBattery(k)
  rearmLevels(k)
end

local function newSessionFor(k)
  ss[k] = newSession()
end

local function addBattery()
  if #bat >= 4 then
    return
  end
  local k = #bat + 1
  bat[k] = newBattery(2)    -- Receiver: the category is the first row
  assignNumber(k)
  recompute(k)
  saveBattery(k)
  newSessionFor(k)
  goTo(k)
end

-- Deleting battery k moves the later ones down (R5).
local function deleteBattery(k)
  table.remove(bat, k)
  table.remove(ss, k)
  table.remove(dv, k)
  for j = k, 4 do
    if bat[j] then
      saveBattery(j)
    else
      clearSlot(j)
    end
  end
  if cfg.smallB == k then
    saveApp("smallB", 1)
  elseif cfg.smallB > k then
    saveApp("smallB", cfg.smallB - 1)
  end
end

-- Not fully set up: no voltage reading, or an mAh source without the pack's
-- capacity (field test 2026-11-08). Shown on the main screen and flashed on
-- the battery's screen.
local function needsSetup(k)
  return not dv[k].hasV or dv[k].noMah
end

local function batterySummary(k)
  local p = bat[k].p
  local text = dv[k].label .. "   " .. catName(p[P.CAT]) .. "   " .. CHEM[p[P.CHEM]].name .. " "
    .. p[P.CELLS] .. "S"
  if needsSetup(k) then
    text = text .. "   SETUP!"
  end
  return text
end

-- A checkbox; the callback gets the old state (Speed Gauge, Flameout).
local function addCheck(label, on, onChange)
  form.addRow(2)
  form.addLabel({ label = label, width = LABEL_W })
  local i
  i = form.addCheckbox(on, function(value)
    local now = not value
    if i then
      form.setValue(i, now)
    end
    onChange(now)
  end)
  return i
end

local function addIntRow(label, value, lo, hi, def, decimals, step, onChange)
  form.addRow(2)
  form.addLabel({ label = label, width = LABEL_W })
  return form.addIntbox(value, lo, hi, def, decimals, step, onChange)
end

local function initMain()
  heading(APP_NAME)
  for k = 1, #bat do
    form.addLink(function() goTo(k) end, { label = batterySummary(k) })
  end
  if #bat < 4 then
    form.addLink(addBattery, { label = "Add battery" })
  end
  if #bat > 0 then
    local labels = {}
    for k = 1, #bat do
      labels[k] = dv[k].label
    end
    form.addRow(2)
    form.addLabel({ label = "Small window shows", width = LABEL_W })
    form.addSelectbox(labels, clamp(cfg.smallB, 1, #bat), false, function(i)
      saveApp("smallB", i)
    end)
  end
  -- Window titles (FR-009a). Windows are registered at start-up, so a new
  -- title shows after the next model load.
  for n = 1, 2 do
    local key = "title" .. n
    form.addRow(2)
    form.addLabel({ label = n == 1 and "Small window title" or "Double window title", width = LABEL_W })
    local title = cfg[key] --[[@as string]]
    form.addTextbox(title ~= "" and title or TITLE[n], TITLE_MAX, function(text)
      if text == TITLE[n] then
        text = ""
      end
      saveApp(key, text)
      note.title = true
      refresh()
    end)
  end
  hint("New titles show after the model is reloaded.", note.title)
  if SIM then                 -- debug only (R13): pick a scripted profile for battery 1
    form.addRow(2)
    form.addLabel({ label = "SIM profile", width = 120 })
    form.addSelectbox(sim.names, sim.idx, false, function(i)
      sim.idx, sim.t0 = i, system.getTimeCounter()
      if ss[1] then
        ss[1].tel = TEL.NONE
      end
    end, { width = 200 })
  end
  -- Voice (FR-031, FR-032): the app voice by default when its files are there.
  heading("Voice")
  form.addRow(2)
  form.addLabel({ label = "Voice", width = LABEL_W })
  local voices = { app.voiceOk and APP_NAME or (APP_NAME .. " (files missing)"), "Transmitter" }
  form.addSelectbox(voices, app.useAppVoice and 1 or 2, false, function(i)
    saveApp("voice", i)
    app.useAppVoice = app.voiceOk and i ~= 2
  end)
  addCheck("Speak number only", cfg.numOnly == 1, function(on)
    saveApp("numOnly", on and 1 or 0)
  end)
  hint("Voice files missing: the transmitter's voice is used.", not app.voiceOk)
  hint("Voice: Piper, Amy (CC BY-SA 4.0).")
  hint(APP_NAME .. " " .. APP_VERSION)
end

-- Capacity hint (FR-004): an mAh source needs the rated capacity. While
-- it's missing, updateFormLive flashes the hint.
local HINT_NOMAH_V = "Capacity (mAh) not set: % from voltage for now."
local HINT_NOMAH = "Set the pack's capacity (mAh)."
local HINT_FROMV = "No capacity sensor: % comes from the voltage sensor."

local function capHintText(k)
  local d = dv[k]
  if d.noMah then
    return d.capFromV and HINT_NOMAH_V or HINT_NOMAH
  end
  if d.capFromV then
    return HINT_FROMV
  end
  return ""
end

local function updateCapHint(k, blank)
  if idx.capHint then
    local text = capHintText(k)
    local shown = text
    if blank and dv[k].noMah then
      shown = " "
    end
    form.setProperties(idx.capHint, { label = shown, visible = text ~= "" })
  end
end

-- Voltage hint: every battery needs a voltage reading (a starting % for
-- mAh counters, low-voltage alarm, new-pack check); flashed while missing.
local HINT_V = "Also gives the % when there's no capacity sensor or mAh."
local HINT_NOV = "Voltage sensor not set: battery not fully set up."

local function updateVHint(k, blank)
  if idx.vHint then
    local text = HINT_V
    if not dv[k].hasV then
      text = blank and " " or HINT_NOV
    end
    form.setProperties(idx.vHint, { label = text })
  end
end

local function onSensor(k, list, i, idField, parField, lblField)
  local b = bat[k]
  b.p[idField], b.p[parField] = list.ids[i], list.pars[i]
  if i == 1 then
    b.s[lblField] = ""
  elseif i ~= list.nf then
    b.s[lblField] = string.sub(list.labels[i], 1, 63)
  end
end

-- Row 32 / F1 on a battery screen: delete after confirming.
local function confirmDelete(k)
  if form.question("Delete " .. dv[k].label .. "?", "Its settings are removed.", "", 0, false, 0) == 1 then
    deleteBattery(k)
    goTo(0)
  end
end

-- Battery screen, essentials first (contracts/settings-form.md rows 1-10,
-- 28-32).
local function initBattery(k)
  local b = bat[k]
  local p, a = b.p, b.a
  buildLists(k)
  heading("Battery " .. k .. ": " .. dv[k].label)

  -- 1 Category
  local catNames, catSel = {}, 1
  for i, id in ipairs(CAT_ORDER) do
    catNames[i] = CAT[id].name
    if id == p[P.CAT] then
      catSel = i
    end
  end
  form.addRow(2)
  form.addLabel({ label = "Category", width = LABEL_W })
  form.addSelectbox(catNames, catSel, true, function(i)
    setCategory(k, CAT_ORDER[i])
    refresh()
  end)

  -- 2 Name (Custom), width-checked (R6)
  if p[P.CAT] == CUSTOM then
    form.addRow(2)
    form.addLabel({ label = "Name", width = LABEL_W })
    form.addTextbox(b.s[S.NAME], 8, function(text)
      local fitted = text
      local num = p[P.NUM] > 0 and ("-" .. p[P.NUM]) or ""
      while fitted ~= "" and not labelFits(fitted .. num) do
        fitted = string.sub(fitted, 1, #fitted - 1)
      end
      b.s[S.NAME] = fitted
      note.short = fitted ~= text
      recompute(k)
      saveBattery(k)
      refresh()
    end)
    hint("Shortened to fit above the battery.", note.short)
  end

  -- 3 Label
  form.addRow(2)
  form.addLabel({ label = "Label", width = LABEL_W })
  form.addLabel({ label = dv[k].label, alignRight = true })

  -- 4 Chemistry, 5 Cells (FR-006, FR-008)
  form.addRow(2)
  form.addLabel({ label = "Chemistry", width = LABEL_W })
  form.addSelectbox(CHEM_NAMES, p[P.CHEM], true, function(i)
    if i ~= p[P.CHEM] then
      p[P.CHEM] = i
      refill(k, E.VOLT | E.LVTHR)
      recompute(k)
      saveBattery(k)
      refresh()
    end
  end)
  addIntRow("Cells", p[P.CELLS], 1, 14, 2, 0, 1, function(value)
    p[P.CELLS] = value
    if a[A.LVMODE] == 2 and (p[P.EDITED] & E.LVTHR) == 0 then
      a[A.LVTHR] = defaultLvThr(b)
    end
    recompute(k)
    saveBattery(k)
  end)
  idx.cells = hint("", false)

  -- 6 Capacity (mAh)
  addIntRow("Capacity (mAh)", p[P.MAH], 0, 30000, 0, 0, 50, function(value)
    local was = dv[k].mode
    p[P.MAH] = value
    recompute(k)
    saveBattery(k)
    if dv[k].mode ~= was then
      ss[k].tel = TEL.NONE      -- switched between the mAh and voltage sources
    end
    updateCapHint(k)
  end)

  -- 7-9 Sensors, filtered by unit (R1, FR-004)
  form.addRow(2)
  form.addLabel({ label = "Capacity sensor", width = 130 })
  form.addSelectbox(lists.cap.labels, lists.cap.sel, true, function(i)
    onSensor(k, lists.cap, i, P.CAPID, P.CAPPAR, S.CAPLBL)
    if i ~= lists.cap.nf then
      p[P.CAPMODE] = CAP_UNITS[lists.cap.units[i]] or M.NONE
    end
    recompute(k)
    saveBattery(k)
    ss[k].tel = TEL.NONE
    refresh()
  end, { width = 180 })
  idx.capHint = hint("", false)
  updateCapHint(k)
  hint("Lists sensors in mAh, Ah, % or V. No sensors? Turn the receiver on.",
    #lists.cap.labels == 1 + #RXV_LABEL)

  form.addRow(2)
  form.addLabel({ label = "Voltage sensor", width = 130 })
  form.addSelectbox(lists.volt.labels, lists.volt.sel, true, function(i)
    onSensor(k, lists.volt, i, P.VID, P.VPAR, S.VLBL)
    recompute(k)
    saveBattery(k)
    if p[P.CAPID] == 0 then
      ss[k].tel = TEL.NONE      -- the % source changed too
    end
    refresh()
  end, { width = 180 })
  idx.vHint = hint(HINT_V)
  updateVHint(k)

  form.addRow(2)
  form.addLabel({ label = "Current sensor", width = 130 })
  form.addSelectbox(lists.cur.labels, lists.cur.sel, true, function(i)
    onSensor(k, lists.cur, i, P.IID, P.IPAR, S.ILBL)
    if i ~= lists.cur.nf then
      if lists.cur.units[i] == "mA" then
        p[P.EDITED] = p[P.EDITED] | E.MA
      else
        p[P.EDITED] = p[P.EDITED] & ~E.MA
      end
    end
    recompute(k)
    saveBattery(k)
    refresh()
  end, { width = 180 })
  hint("When set, the 4-battery window shows current, not voltage.")

  -- 10 Live value, updated from loop() while the form is open
  form.addRow(2)
  form.addLabel({ label = "Now", width = LABEL_W })
  idx.live = form.addLabel({ label = TXT.dash, alignRight = true })

  -- 11-16 Capacity callouts (FR-016 - FR-018)
  heading("Capacity callouts")
  local function levelsOk()
    local prev = 100
    for i = 1, 4 do
      if levelOn(a, i) then
        if a[A.LVL1 + i - 1] >= prev then
          return false
        end
        prev = a[A.LVL1 + i - 1]
      end
    end
    return true
  end
  -- Applies a level change, or reverts it with a note (R11).
  local function levelChanged(revert)
    if not levelsOk() then
      revert()
      note.levels = true
      refresh()
      return
    end
    note.levels = false
    p[P.EDITED] = p[P.EDITED] | E.LVL
    recompute(k)
    saveBattery(k)
    rearmLevels(k)
  end
  for i = 1, 4 do
    local field = A.LVL1 + i - 1
    local bit = 1 << (i - 1)
    form.addRow(3)
    form.addLabel({ label = "Level " .. i .. " (%)", width = 150 })
    local ci
    ci = form.addCheckbox(levelOn(a, i), function(value)
      local on = not value      -- the callback gets the old state
      if ci then
        form.setValue(ci, on)
      end
      a[A.LVLON] = on and (a[A.LVLON] | bit) or (a[A.LVLON] & ~bit)
      levelChanged(function()
        a[A.LVLON] = a[A.LVLON] ~ bit
      end)
    end, { width = 40 })
    form.addIntbox(a[field], 1, 99, a[field], 0, 1, function(value)
      local old = a[field]
      a[field] = value
      levelChanged(function()
        a[field] = old
      end)
    end, { width = 110 })
  end
  hint("Levels must go down, e.g. 60 > 50 > 40 > 30.", note.levels)
  if a[A.SHOWALL] == 1 then
    addIntRow("Repeat lowest every (s)", a[A.RPT], 3, 60, 5, 0, 1, function(value)
      a[A.RPT] = value
      saveBattery(k)
    end)
    addIntRow("Max repeats", a[A.MAXCNT], 0, 20, 0, 0, 1, function(value)
      a[A.MAXCNT] = value
      saveBattery(k)
    end)
    hint("0 = no limit. Also limits the low-voltage alarm.")
  end

  -- 17-19 Low voltage (FR-019, FR-020), only with a voltage reading
  if dv[k].hasV then
    heading("Low voltage")
    form.addRow(2)
    form.addLabel({ label = "Low-voltage alarm", width = LABEL_W })
    form.addSelectbox({ "Off", "Per cell", "Per pack" }, a[A.LVMODE] + 1, false, function(i)
      local old, new = a[A.LVMODE], i - 1
      -- Off and per cell keep the threshold per cell; per pack is the pack
      -- voltage. Convert when crossing between them (FR-019).
      if new == 2 and old ~= 2 then
        a[A.LVTHR] = a[A.LVTHR] * p[P.CELLS]
      elseif old == 2 and new ~= 2 then
        a[A.LVTHR] = (a[A.LVTHR] + p[P.CELLS] // 2) // p[P.CELLS]
      end
      a[A.LVMODE] = new
      ss[k].lvOn, ss[k].lvBelowT, ss[k].lvAboveT = false, nil, nil
      recompute(k)
      saveBattery(k)
      refresh()
    end)
    if a[A.LVMODE] == 1 then
      addIntRow("Threshold (V per cell)", a[A.LVTHR], 50, 500, a[A.LVTHR], 2, 1, function(value)
        a[A.LVTHR] = value
        p[P.EDITED] = p[P.EDITED] | E.LVTHR
        recompute(k)
        saveBattery(k)
      end)
    elseif a[A.LVMODE] == 2 then
      -- Shown in tenths of a volt (FR-021: one decimal per pack), stored in cV.
      addIntRow("Threshold (V pack)", (a[A.LVTHR] + 5) // 10, 5, 999, (a[A.LVTHR] + 5) // 10, 1, 1,
        function(value)
          a[A.LVTHR] = value * 10
          p[P.EDITED] = p[P.EDITED] | E.LVTHR
          recompute(k)
          saveBattery(k)
        end)
    end
    if a[A.LVMODE] > 0 and a[A.SHOWALL] == 1 then
      addIntRow("Alarm delay (s)", a[A.LVDLY], 5, 100, 20, 1, 1, function(value)
        a[A.LVDLY] = value
        saveBattery(k)
      end)
    end
  end

  -- 20-25 Current (FR-024 - FR-027), only with a current sensor; hidden for
  -- categories without current-alarm rows unless "Show all" (FR-007)
  if dv[k].hasI and (dv[k].cat.cur or a[A.SHOWALL] == 1) then
    heading("Current")
    local function missing()
      local parts = {}
      if a[A.ITHR] == 0 then
        parts[#parts + 1] = "threshold"
      end
      if a[A.IDLY] == 0 then
        parts[#parts + 1] = "delay"
      end
      if a[A.IRPT] == 0 then
        parts[#parts + 1] = "repeat"
      end
      if #parts == 0 or #parts == 3 then
        return ""             -- complete, or simply not used
      end
      return "Current alarm off: set " .. table.concat(parts, ", ") .. "."
    end
    local function currentChanged()
      recompute(k)
      saveBattery(k)
      local text = missing()
      form.setProperties(idx.iMissing, { label = text, visible = text ~= "" })
    end
    addIntRow("Alarm above (A)", a[A.ITHR], 0, 500, 0, 0, 1, function(value)
      a[A.ITHR] = value
      currentChanged()
    end)
    addIntRow("for (s)", a[A.IDLY], 0, 100, 0, 1, 1, function(value)
      a[A.IDLY] = value
      currentChanged()
    end)
    addIntRow("repeat every (s)", a[A.IRPT], 0, 60, 0, 0, 1, function(value)
      a[A.IRPT] = value
      currentChanged()
    end)
    local text = missing()
    idx.iMissing = hint(text, text ~= "")
    hint("0 = off. The alarm needs all three set.", a[A.ITHR] + a[A.IDLY] + a[A.IRPT] == 0)
    addCheck("Max current callouts", a[A.MAXON] == 1, function(on)
      a[A.MAXON] = on and 1 or 0
      saveBattery(k)
    end)
    if a[A.SHOWALL] == 1 then
      addIntRow("Max sensitivity (A)", a[A.MAXSENS], 1, 50, 5, 0, 1, function(value)
        a[A.MAXSENS] = value
        saveBattery(k)
      end)
    end
    form.addLink(function()
      resetMax(k)
      system.messageBox("Max current reset", 2)
    end, { label = "Reset max current" })
  end

  -- 26-27 New pack (FR-029), only with a voltage reading
  if dv[k].hasV then
    heading("New pack")
    addCheck("Check pack is full", a[A.NPON] == 1, function(on)
      a[A.NPON] = on and 1 or 0
      saveBattery(k)
    end)
    hint("Says once if a newly connected pack isn't charged (3 s after it's seen).")
    if a[A.SHOWALL] == 1 then
      addIntRow("Full above (%)", a[A.NPTHR], 50, 99, 90, 0, 1, function(value)
        a[A.NPTHR] = value
        saveBattery(k)
      end)
    end
  end

  -- 28 Name for the transmitter voice (FR-033)
  heading("Voice")
  form.addRow(2)
  form.addLabel({ label = "Name file (transmitter voice)", width = LABEL_W })
  form.addAudioFilebox(b.s[S.VOICE], function(fileName)
    b.s[S.VOICE] = fileName or ""
    saveBattery(k)
  end)
  hint("Played before the number when the transmitter's voice speaks.")

  -- 29-30 Advanced: bands and voltages (FR-006, FR-007), with Show all
  if a[A.SHOWALL] == 1 then
    heading("Colour bands (% remaining)")
    local function band(label, field)
      addIntRow(label, p[field], 1, 99, p[field], 0, 1, function(value)
        local old = p[field]
        p[field] = value
        if not (p[P.BANDY] > p[P.BANDO] and p[P.BANDO] > p[P.BANDR]) then
          p[field] = old      -- bands must go down (R11): revert and say why
          note.band = true
          refresh()
          return
        end
        note.band = false
        p[P.EDITED] = p[P.EDITED] | E.BAND
        saveBattery(k)
      end)
    end
    band("Yellow below", P.BANDY)
    band("Orange below", P.BANDO)
    band("Red below", P.BANDR)
    hint("Bands must go down: yellow > orange > red.", note.band)

    heading("Voltages per cell")
    local function volt(label, field)
      addIntRow(label, p[field], 50, 500, p[field], 2, 1, function(value)
        p[field] = value
        p[P.EDITED] = p[P.EDITED] | E.VOLT
        if field == P.VWARN and (p[P.EDITED] & E.LVTHR) == 0 then
          a[A.LVTHR] = defaultLvThr(b)
        end
        recompute(k)
        saveBattery(k)
      end)
    end
    volt("Full (charged)", P.VFULL)
    volt("Nominal", P.VNOM)
    volt("Warning", P.VWARN)
    volt("Cutoff (0 %)", P.VCUT)
  end

  -- 31 Show all settings, 32 Delete battery
  heading("Battery")
  addCheck("Show all settings", a[A.SHOWALL] == 1, function(on)
    a[A.SHOWALL] = on and 1 or 0
    saveBattery(k)
    refresh()
  end)
  form.addLink(function() confirmDelete(k) end, { label = "Delete battery" })
  form.setButton(1, "Delete", ENABLED)   -- also on F1: the link is the last row
end

local function initForm()
  formOpen = true
  idx = {}
  if cur > #bat then
    cur = 0
  end
  if cur == 0 then
    form.setButton(1, "", 3)  -- hide F1's "Delete" from a battery screen
    initMain()
  else
    initBattery(cur)
  end
  if keepRow then
    form.setFocusedRow(keepRow)
    keepRow = nil
  end
end

-- On a battery screen: F5 / ESC go back to the main page (R12), F1
-- deletes the battery after confirming.
local function keyForm(keyCode)
  if cur == 0 then
    return
  end
  if keyCode == KEY_ESC or keyCode == KEY_5 then
    form.preventDefault()
    goTo(0)
  elseif keyCode == KEY_1 then
    confirmDelete(cur)
  end
end

local function closeForm()
  formOpen = false
  idx = {}
  note.short, note.band, note.title, note.levels = false, false, false, false
  cur = 0
end

-- Form rows updated each slow tick while the form shows battery k: live
-- value (row 10) and the cell-count check (R11).
local function updateFormLive(k)
  if not formOpen or cur ~= k or not idx.live then
    return
  end
  local s, d, p = ss[k], dv[k], bat[k].p
  local text = s.txtPct
  if s.txtSmall ~= "" then
    text = text .. "   " .. s.txtSmall
  end
  form.setProperties(idx.live, { label = text })
  if idx.cells then
    local warn = ""
    if d.hasV and s.vNow then
      local vc = s.vNow / p[P.CELLS]
      if vc > p[P.VFULL] + 10 or vc < p[P.VCUT] - 30 then
        warn = string.format("Check cell count: reads %.1f V", s.vNow / 100)
      end
    end
    form.setProperties(idx.cells, { label = warn, visible = warn ~= "" })
  end
  if needsSetup(k) then
    app.hintBlank = not app.hintBlank
    updateCapHint(k, app.hintBlank)
    updateVHint(k, app.hintBlank)
  end
end

------------------------------------------------------------------------------
-- Telemetry windows (contracts/telemetry-window.md). The only place lcd is
-- used.
------------------------------------------------------------------------------

local fg = { 0, 0, 0 }      -- neutral outline/text colour, set once per frame
local NEUTRAL = { light = 30, dark = 235 }   -- grey levels on light / dark backgrounds

local function setColor(c, alpha)
  lcd.setColor(c[1], c[2], c[3], alpha)
end

-- FR-012a: dark grey on a light theme, light grey on a dark one.
-- getFgColor() isn't used: on the DS-24 II it is the theme's accent colour
-- (green or red), and red outlines would look like the low-voltage flash.
local function readTheme()
  local r, g, b = lcd.getBgColor()
  local v = NEUTRAL.dark
  if 299 * r + 587 * g + 114 * b > 128000 then
    v = NEUTRAL.light
  end
  fg[1], fg[2], fg[3] = v, v, v
end

-- Outline colour: red on the flash phase of a low-voltage alarm (FR-022),
-- grey when the battery has no live data, else the theme colour.
local function outlineColor(s, live)
  if live and s.lvOn and (system.getTimeCounter() // 500) % 2 == 0 then
    setColor(RED)
  elseif live then
    setColor(fg)
  else
    setColor(fg, 100)
  end
end

-- The % text over a fill whose edge may pass through it (FR-013): drawn
-- twice, clipped to the filled and the empty part. setClipping moves the
-- origin to the clip corner, so coordinates are offset (API notes).
local function drawSplitText(tx, ty, text, font, fx, fy, fw, fh, band)
  local tw, th = lcd.getTextWidth(font, text), lcd.getTextHeight(font)
  local inFill = tx >= fx and tx + tw <= fx + fw and ty >= fy and ty + th <= fy + fh
  local outFill = fw <= 0 or fh <= 0 or tx >= fx + fw or tx + tw <= fx or ty >= fy + fh or ty + th <= fy
  if inFill then
    setColor(BAND_TXT[band])
    lcd.drawText(tx, ty, text, font)
  elseif outFill then
    setColor(fg)
    lcd.drawText(tx, ty, text, font)
  else
    setColor(fg)
    lcd.drawText(tx, ty, text, font)
    lcd.setClipping(fx, fy, fw, fh)
    setColor(BAND[band])
    lcd.drawFilledRectangle(0, 0, fw, fh)
    setColor(BAND_TXT[band])
    lcd.drawText(tx - fx, ty - fy, text, font)
    lcd.resetClipping()
  end
end

local function drawCentered(cx, y, text, font)
  lcd.drawText(cx - lcd.getTextWidth(font, text) // 2, y, text, font)
end

-- Fill size in px for `pct` over `full` px, rounded; never thinner than
-- L.minFill at 0-2 % (FR-012).
local function fillSize(full, pct)
  local n = (full * pct + 50) // 100
  if pct <= L.minFillPct and n < L.minFill then
    return L.minFill
  end
  return n
end

-- Small window (150 x 23): one battery on its side (FR-010).
local function drawSmall(ox, k)
  local s = ss[k]
  local live = s.tel == TEL.LIVE
  outlineColor(s, live)
  lcd.drawRectangle(ox + L.sx, L.sy, L.sw, L.sh, 2)
  lcd.drawFilledRectangle(ox + L.capX, L.capY, L.capW, L.capH)
  local cx = ox + L.sx + L.sw // 2
  if live then
    local fw = fillSize(L.sfw, s.pct)
    if fw > 0 then
      setColor(BAND[s.band])
      lcd.drawFilledRectangle(ox + L.sfx, L.sfy, fw, L.sfh)
    end
    local tx = cx - lcd.getTextWidth(FONT_NORMAL, s.txtPct) // 2
    drawSplitText(tx, L.sPctY, s.txtPct, FONT_NORMAL, ox + L.sfx, L.sfy, fw, L.sfh, s.band)
    setColor(fg)
  else
    setColor(fg, 100)
    local text = s.tel == TEL.LOST and TXT.noTel or TXT.dash
    drawCentered(cx, L.sy + (L.sh - lcd.getTextHeight(FONT_MINI)) // 2, text, FONT_MINI)
  end
  lcd.drawText(ox + L.stx, L.sLabelY, dv[k].label, FONT_MINI)
  lcd.drawText(ox + L.stx, L.sValY, s.txtSmall, FONT_MINI)
end

local function windowSetup(w, h)
  readTheme()
  local ox = 0
  if w == 157 then            -- emulator: title inside the window
    h = h - TITLE_H
    ox = 3
  end
  if not app.gaugeOk or #bat == 0 then
    setColor(fg)
    lcd.drawText(ox + 2, 2, app.gaugeOk and TXT.noBat or TXT.needs, FONT_MINI)
    return nil, h
  end
  return ox, h
end

local function printSmall(w, h)
  local ox = windowSetup(w, h)
  if ox then
    drawSmall(ox, clamp(cfg.smallB, 1, #bat))
  end
end

-- One upright battery in slot k of the double window (FR-011). Slots keep
-- their four-battery positions; unused slots draw nothing.
local function drawUpright(ox, k)
  local s = ss[k]
  local live = s.tel == TEL.LIVE
  local x0 = ox + 1 + (k - 1) * L.slotW
  local cx = x0 + L.slotW // 2
  if live then
    setColor(fg)
  else
    setColor(fg, 100)
  end
  drawCentered(cx, L.dLabelY, dv[k].label, FONT_MINI)
  outlineColor(s, live)
  lcd.drawFilledRectangle(cx - L.dCapW // 2, L.dCapY, L.dCapW, L.dCapH)
  lcd.drawRectangle(x0 + L.dx, L.dy, L.dw, L.dh, 2)
  if live then
    local fh = fillSize(L.dfh, s.pct)
    local fy = L.dfBottom - fh
    if fh > 0 then
      setColor(BAND[s.band])
      lcd.drawFilledRectangle(x0 + L.dfx, fy, L.dfw, fh)
    end
    local tx = cx - lcd.getTextWidth(FONT_MINI, s.txtPct) // 2
    drawSplitText(tx, L.dPctY, s.txtPct, FONT_MINI, x0 + L.dfx, fy, L.dfw, fh, s.band)
    setColor(fg)
  else
    setColor(fg, 100)
    if s.tel == TEL.LOST then
      drawCentered(cx, L.dNoY, TXT.no, FONT_MINI)
      drawCentered(cx, L.dTelY, TXT.telem, FONT_MINI)
    else
      drawCentered(cx, L.dTelY, TXT.dash, FONT_MINI)
    end
  end
  drawCentered(cx, L.dLineY, s.txtLine, FONT_MINI)
end

-- Double window (150 x 68): up to four upright batteries.
local function printDouble(w, h)
  local ox = windowSetup(w, h)
  if not ox then
    return
  end
  for k = 1, #bat do
    drawUpright(ox, k)
  end
  if DEBUG_CPU then
    local cpu = system.getCPU()
    app.cpuWorst = math.max(app.cpuWorst, cpu)
    lcd.drawText(ox + 100, 56, string.format("CPU %d/%d", cpu, app.cpuWorst), FONT_MINI)
  end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function init()
  loadSettings()
  dv = {}
  recomputeAll()
  resetSessions()
  -- Gauges on the DS/DC-24 family, II and first version: both report
  -- about 150 x 23 / 150 x 68 windows (API notes, 2026-11-05). Callouts work
  -- on any transmitter.
  app.gaugeOk = string.find(system.getDeviceType() or "", "24", 1, true) ~= nil
  checkVoice()              -- once: 19 file opens (R9)
  local now = system.getTimeCounter()
  app.fastT, app.slowT = now, now

  system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm, nil, closeForm)
  system.registerTelemetry(1, cfg.title1 ~= "" and cfg.title1 or TITLE[1], 1, printSmall)
  system.registerTelemetry(2, cfg.title2 ~= "" and cfg.title2 or TITLE[2], 2, printDouble)
end

local function loop()
  if #bat == 0 then
    return
  end
  local now = system.getTimeCounter()
  if now - app.fastT < T.FAST then
    return
  end
  app.fastT = now
  readSensors(now)
  for k = 1, #bat do
    updateLowVoltage(k, now)
    updateCurrent(k, now)
  end
  -- Dispatch as soon as playback ends, not only on the slow tick (R9).
  local playing = system.isPlayback()
  if app.playing and not playing then
    dispatch(now)
  end
  app.playing = playing

  if now - app.slowT >= T.SLOW then
    app.slowT = now
    for k = 1, #bat do
      updateCapacity(k, now)
      if ss[k].tel == TEL.LIVE then
        updateLevels(k, now)
        updateMax(k, now)
        updatePackCheck(k, now)
      end
      updateStrings(k)
      updateFormLive(k)
    end
    dispatch(now)
  end
  if DEBUG_CPU then
    local cpu = system.getCPU()
    if cpu > app.cpuWorst then
      app.cpuWorst = cpu
      print("BatCp loop CPU " .. cpu)
    end
  end
end

local function destroy()
  formOpen = false
end

---@type JetiApp
return {
  init = init,
  loop = loop,
  destroy = destroy,
  author = "Aaron George",
  version = APP_VERSION,
  name = APP_NAME,
}
