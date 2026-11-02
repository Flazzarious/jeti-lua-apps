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
}

-- The JETI Studio emulator draws each window's title inside the reported
-- canvas (157 x 127 / 157 x 60); the transmitter draws it above and reports
-- 150 x 68 / 150 x 23 (Speed Gauge, 2026-10-03).
local TITLE_H = 26

local TXT = {
  noTel = "NO TELEM", no = "NO", telem = "TELEM", dash = "--",
  noBat = "Add a battery in settings", needs = "Battery Capacity needs DS-24 II",
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

-- FONT_MINI advance widths in Lua px, for the label fit check (R6).
-- ESTIMATED until measured on the transmitter (tasks T002, PROBE MODE 6).
local MINI_W = {}
local MINI_W_DEFAULT = { upper = 7, digit = 6, other = 7, ["-"] = 4, [" "] = 3 }

-- Layout (contracts/telemetry-window.md), transmitter coordinates.
local L = {
  slotW = 37,               -- double window: one battery slot
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

local function charWidth(ch)
  local w = MINI_W[ch] or MINI_W_DEFAULT[ch]
  if w then
    return w
  elseif ch:match("%u") then
    return MINI_W_DEFAULT.upper
  elseif ch:match("%d") then
    return MINI_W_DEFAULT.digit
  end
  return MINI_W_DEFAULT.other
end

-- Label width in FONT_MINI from MINI_W (R6); lcd isn't available in form
-- callbacks, so the form measures with this table.
local function labelWidth(text)
  local w = 0
  for i = 1, #text do
    w = w + charWidth(string.sub(text, i, i))
  end
  return w
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
}

local function newSession()
  local s = {
    tel = TEL.NONE, badSince = nil,
    capVal = nil, capOk = false,
    pct = 0, pctLast = 0, vPct = nil, vPctLast = nil,
    vSum = 0, vN = 0, vNow = nil, vEst = nil,
    iNow = nil, band = 1,
    fired = 0, rptN = 0, rptT = 0,
    lvBelowT = nil, lvAboveT = nil, lvOn = false,
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

-- Raw % from the capacity source's last reading; nil when it can't be
-- computed (no rated capacity for an mAh source).
local function rawPct(k, value)
  local b, d = bat[k], dv[k]
  local mAh = b.p[P.MAH]
  if d.mode == M.MAH or d.mode == M.AH then
    if mAh <= 0 then
      return nil
    end
    local used = value
    if d.mode == M.AH then
      used = value * 1000
    end
    return (mAh - used) * 100 / mAh
  elseif d.mode == M.PCT then
    return value
  elseif d.mode == M.VOLT then
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
  names = { "Off", "1 Discharge", "2 Noisy voltage" },
  noise = { false, false, true },
  prof = {
    {},
    { { 0, 100, 415, 5 }, { 300000, 0, 350, 5 } },
    { { 0, 90, 334, 0 }, { 120000, 50, 329, 0 }, { 240000, 10, 315, 0 } },
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

local function speak(k, kind, value)
  speakTransmitter(k, kind, value)
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
  s.fired, s.rptN, s.rptT = 0, 0, 0
  s.lvBelowT, s.lvAboveT, s.lvOn = nil, nil, false
  s.iAboveT, s.iAlarm = nil, false
  peak.reset(s.peak)
  s.riseT, s.lastAnn = 0, 0
  s.npDueT, s.npDone = now + T.NP_DELAY, false
  clearPending(k)
end

-- Fast tick: read each assigned sensor once (always through system, R3 of
-- Speed Gauge: the emulator's telemetry app replaces these functions).
local function readSensors(now)
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
      if p[P.CAPID] ~= 0 then
        local v = system.getSensorValueByID(p[P.CAPID], p[P.CAPPAR])
        if v ~= nil and v.valid then
          cap = v.value
        end
      end
      if d.voltSrc == 1 then
        local v = system.getSensorValueByID(p[P.VID], p[P.VPAR])
        if v ~= nil and v.valid then
          volts = v.value
        end
      elseif d.voltSrc == 2 then
        volts = cap
      end
      if d.hasI then
        local v = system.getSensorValueByID(p[P.IID], p[P.IPAR])
        if v ~= nil and v.valid then
          amps = v.value * d.iScale
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

  if d.mode == M.NONE then
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
  local raw = rawPct(k, s.capVal)
  if raw == nil then
    return
  end
  if s.tel == TEL.NONE then
    s.tel = TEL.LIVE
    startPackSession(k, now, roundPct(raw))
  elseif s.tel == TEL.LOST then
    s.tel = TEL.LIVE
    -- New pack: 20 points higher, and with a separate voltage sensor the
    -- voltage estimate agrees (R4). Otherwise a brown-out: keep everything.
    local isNew = raw >= s.pctLast + T.NEWPACK
    if isNew and d.voltSrc == 1 and s.vPct ~= nil and s.vPctLast ~= nil then
      isNew = s.vPct >= s.vPctLast + T.NEWPACK
    end
    if isNew then
      startPackSession(k, now, roundPct(raw))
    end
  end
  -- Voltage source: smoothed (10 s time constant), held under load (R3).
  if d.mode == M.VOLT then
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
local note = { short = false, band = false, title = false }   -- one-off notes for this form session
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
  p[P.CAT] = cat
  assignNumber(k)
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

local function batterySummary(k)
  local p = bat[k].p
  return dv[k].label .. "   " .. catName(p[P.CAT]) .. "   " .. CHEM[p[P.CHEM]].name .. " "
    .. p[P.CELLS] .. "S"
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
  hint(APP_NAME .. " " .. APP_VERSION)
end

-- Capacity hint (FR-004): an mAh source needs the rated capacity.
local function capHintText(k)
  local d = dv[k]
  if (d.mode == M.MAH or d.mode == M.AH) and bat[k].p[P.MAH] <= 0 then
    return "Set the pack's capacity (mAh)."
  end
  return ""
end

local function updateCapHint(k)
  if idx.capHint then
    local text = capHintText(k)
    form.setProperties(idx.capHint, { label = text, visible = text ~= "" })
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
    p[P.MAH] = value
    recompute(k)
    saveBattery(k)
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
    #lists.cap.labels == 1)

  form.addRow(2)
  form.addLabel({ label = "Voltage sensor", width = 130 })
  form.addSelectbox(lists.volt.labels, lists.volt.sel, true, function(i)
    onSensor(k, lists.volt, i, P.VID, P.VPAR, S.VLBL)
    recompute(k)
    saveBattery(k)
    refresh()
  end, { width = 180 })

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

  -- 10 Live value, updated from loop() while the form is open
  form.addRow(2)
  form.addLabel({ label = "Now", width = LABEL_W })
  idx.live = form.addLabel({ label = TXT.dash, alignRight = true })

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
  form.addLink(function()
    if form.question("Delete " .. dv[k].label .. "?", "Its settings are removed.", "", 0, false, 0) == 1 then
      deleteBattery(k)
      goTo(0)
    end
  end, { label = "Delete battery" })
end

local function initForm()
  formOpen = true
  idx = {}
  if cur > #bat then
    cur = 0
  end
  if cur == 0 then
    initMain()
  else
    initBattery(cur)
  end
  if keepRow then
    form.setFocusedRow(keepRow)
    keepRow = nil
  end
end

-- F5 / ESC on a battery screen go back to the main page (R12).
local function keyForm(keyCode)
  if cur ~= 0 and (keyCode == KEY_ESC or keyCode == KEY_5) then
    form.preventDefault()
    goTo(0)
  end
end

local function closeForm()
  formOpen = false
  idx = {}
  note.short, note.band, note.title = false, false, false
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
end

------------------------------------------------------------------------------
-- Telemetry windows (contracts/telemetry-window.md). The only place lcd is
-- used.
------------------------------------------------------------------------------

local fg = { 0, 0, 0 }      -- theme foreground, read once per frame

local function setColor(c, alpha)
  lcd.setColor(c[1], c[2], c[3], alpha)
end

local function readTheme()
  fg[1], fg[2], fg[3] = lcd.getFgColor()
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

-- Small window (150 x 23): one battery on its side (FR-010).
local function drawSmall(ox, k)
  local s = ss[k]
  local live = s.tel == TEL.LIVE
  outlineColor(s, live)
  lcd.drawRectangle(ox + L.sx, L.sy, L.sw, L.sh, 2)
  lcd.drawFilledRectangle(ox + L.capX, L.capY, L.capW, L.capH)
  local cx = ox + L.sx + L.sw // 2
  if live then
    local fw = (L.sfw * s.pct + 50) // 100
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
    local fh = (L.dfh * s.pct + 50) // 100
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
  app.gaugeOk = string.find(system.getDeviceType() or "", "24 II", 1, true) ~= nil
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
