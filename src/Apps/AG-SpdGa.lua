-- AG-SpdGa.lua — Speed Gauge: speed callouts, stall/overspeed warnings and a speedometer telemetry window.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Based on DFM Speed Announcer v2.1 by DFM (Dave McQueeney),
-- https://github.com/davidmcq137/JetiLuaDFM
-- Portions Copyright (c) 2018, 2019 DFM (Dave McQueeney), MIT License.
-- Full license text in CREDITS.md.
--
-- Listen-and-inform only: it reads a speed sensor and switches, speaks,
-- vibrates the sticks and draws. It never controls the model
-- (constitution principle I).
--
-- Design: specs/001-speed-gauge/ (plan.md, research.md, data-model.md,
-- contracts/). Research decisions are cited as R1..R12.

local gauge = require("ag_gauge")
local dens = require("ag_dens")

local APP_NAME = "Speed Gauge"
local APP_VERSION = "0.1.0"
local AUDIO_DIR = "/Apps/AG-SpdGa/"
local TICK_MS = 100         -- loop logic runs at most 10x per second (R9)
-- The DS-24 II desktop draws each window's title bar inside the reported
-- canvas and clips the bottom: about 25 px of h is never visible (measured
-- in the emulator, 2026-09-27: 60 -> ~34, 127 -> ~101, 260 -> ~236).
local TITLE_H = 26
local HOLD_MS = 1000        -- a reading held this long counts as real for the max (R5)

local SND_STALL = AUDIO_DIR .. "stall_warning.wav"
local SND_OVER = AUDIO_DIR .. "overspeed.wav"
local SND_ALIVE = AUDIO_DIR .. "airspeed_alive.wav"
local SND_CAL = AUDIO_DIR .. "airspeed_cal_factor.wav"
local SND_STALL_AT = AUDIO_DIR .. "stall_speed_warning_at.wav"

-- Units. The sensor value is m/s, as in DFM v2.1 (R3).
local UNITS_TEXT = { "mph", "km/h", "kt", "m/s", "ft/s" }
local UNITS_SPOKEN = { "mph", "km/h", "kt.", "m/s", "ft./s" }  -- must match numbers.jsn
local UNITS_MULT = { 2.23694, 3.6, 1.94384, 1.0, 3.28084 }
local UNITS_IMPERIAL = { true, false, true, false, true }

-- Color presets for a dark dial face; none red, orange or yellow (R8).
-- Yellow was added last so earlier saved indices keep their color.
local COLOR_NAMES = { "Cyan", "Blue", "White", "Green", "Lime", "Magenta", "Purple", "Grey", "Yellow" }
local COLORS = {
  { 0, 190, 255 }, { 40, 110, 255 }, { 255, 255, 255 }, { 0, 210, 100 },
  { 170, 240, 0 }, { 230, 60, 230 }, { 150, 100, 255 }, { 170, 170, 170 },
  { 255, 225, 0 },
}
-- Fixed dial colors (R6).
local C_BG = { 8, 10, 14 }       -- window background behind the dial face
local C_FACE = { 20, 24, 32 }
local C_TRACK = { 70, 78, 90 }
local C_ZONE = { 255, 80, 0 }
local C_SCALE = { 200, 200, 200 }
local C_MINOR = { 110, 118, 130 }
local C_TEXT = { 255, 255, 255 }
-- Glow inside the value arc: bands fading toward the dial center (reference
-- image). Alpha per band, outermost first.
local GLOW_ALPHA = { 0.42, 0.30, 0.21, 0.14, 0.09, 0.055, 0.03, 0.015 }

local TXT_NOTICE = "Speed Gauge needs DS-24 II"
local TXT_MAX = "MAX"
local TXT_STALL = "STALL"
local TXT_OVR = "OVR"
local TXT_OVERSPEED = "OVERSPEED"
local TXT_DENSITY = "AIR DENSITY"
local TXT_SENSOR = "RAW SENSOR"
local TXT_ELEVATION = "ELEVATION"
local TXT_OFF = "OFF"
local TXT_GPS = "GPS"
local TXT_NO_DATA = "---"

------------------------------------------------------------------------------
-- Settings (persisted per model; data-model.md). Integers, strings and
-- SwitchItems only; booleans are stored as 0/1 (constitution IV).
------------------------------------------------------------------------------

local KEYS = {
  "sId", "sPar", "sLbl", "sType", "swOn", "swCont", "tMin", "tMax", "sens",
  "vLand", "vStall", "vOver", "cal", "units", "numOnly", "startAnn", "densOn",
  "elev", "temp", "tStd", "colCur", "colMax", "fScale", "cfgV",
}
local DEFAULTS = {
  sId = 0, sPar = 0, sLbl = "", sType = 1, tMin = 2, tMax = 40, sens = 10,
  vLand = 60, vStall = 45, vOver = 200, cal = 100, units = 1, numOnly = 0,
  startAnn = 1, densOn = 0, elev = 0, tStd = 1, colCur = 1, colMax = 9,
  fScale = 0, cfgV = 1,
}  -- swOn / swCont default to nil; temp depends on units

local cfg = {}

local function save(key, value)
  cfg[key] = value
  system.pSave(key, value)
end

local function loadSettings()
  for _, key in ipairs(KEYS) do
    cfg[key] = system.pLoad(key, DEFAULTS[key])
  end
  if cfg.temp == nil then
    cfg.temp = UNITS_IMPERIAL[cfg.units] and 59 or 15
  end
end

------------------------------------------------------------------------------
-- Derived values: recomputed only when a setting changes, never per tick.
------------------------------------------------------------------------------

local kSensor = 1           -- sensor m/s -> calibrated speed in the user's units
local kDens = 1             -- true airspeed / sensor speed (R1)
local fullScale = 230
local fStall, fLand, fOver = 0, 0, 1   -- dial fractions (FR-016a)
local scaleStep = 50
local scaleLabels = {}      -- major tick label strings
local scaleVer = 0          -- bumped whenever the dial scale changes
local unitText = "mph"
local unitSpoken = "mph"
local densPctText = "+0%"
local densActive = false    -- correction on and an airspeed sensor
local densRowText = "OFF"   -- full-screen AIR DENSITY row: "+8%", "OFF" or "GPS"
local elevText, elevUnitText = "0", "ft"
local stallText, overText = "45", "200"

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

local function recomputeSensor()
  kSensor = UNITS_MULT[cfg.units] * cfg.cal / 100
end

local function recomputeDensity()
  local imperial = UNITS_IMPERIAL[cfg.units]
  densActive = cfg.densOn == 1 and cfg.sType == 1
  if densActive then
    local elevM = imperial and dens.ftToM(cfg.elev) or cfg.elev
    local tempC = nil
    if cfg.tStd ~= 1 then
      tempC = imperial and dens.fToC(cfg.temp) or cfg.temp
    end
    kDens = dens.factor(elevM, tempC)
  else
    kDens = 1
  end
  local pct = math.floor((kDens - 1) * 100 + 0.5)
  densPctText = (pct >= 0 and "+" or "") .. pct .. "%"
  if cfg.sType == 2 then
    densRowText = TXT_GPS
  elseif densActive then
    densRowText = densPctText
  else
    densRowText = TXT_OFF
  end
  elevText = tostring(cfg.elev)
  elevUnitText = imperial and "ft" or "m"
end

local function recomputeScale()
  local fs = cfg.fScale
  if fs == 0 then
    fs = math.ceil(cfg.vOver * 1.15 / 10) * 10
  end
  fs = math.max(fs, 10)
  fullScale = fs
  fStall = clamp(cfg.vStall * kDens / fs, 0, 1)
  fLand = clamp(cfg.vLand * kDens / fs, 0, 1)
  fOver = clamp(cfg.vOver / fs, 0, 1)
  scaleStep = gauge.scaleStep(fs)
  local labels = {}
  for i = 0, fs // scaleStep do
    labels[i + 1] = tostring(math.floor(i * scaleStep))
  end
  scaleLabels = labels
  stallText = tostring(cfg.vStall)
  overText = tostring(cfg.vOver)
  scaleVer = scaleVer + 1
end

local function recomputeUnitText()
  unitText = UNITS_TEXT[cfg.units]
  unitSpoken = UNITS_SPOKEN[cfg.units]
end

local function recomputeAll()
  recomputeSensor()
  recomputeDensity()
  recomputeScale()
  recomputeUnitText()
end

------------------------------------------------------------------------------
-- Session state (not persisted; reset by init on every model load).
------------------------------------------------------------------------------

local sensorSpd = nil       -- calibrated sensor speed; nil = no data
local shownSpd = nil        -- sensorSpd * kDens: shown, spoken, max, overspeed
local maxSpd = 0
local prevDistinct = nil    -- previous distinct shownSpd, for spike filtering (R5)
local distinctSince = 0     -- when shownSpd last changed
local everAboveHalf = false
local everAboveLanding = false
local belowLanding = false
local aliveSaid = false
local stallArmed = true
local overArmed = true
local lastSpokenSpd = 0
local lastSpokenAt = nil    -- nil = nothing spoken yet this session
local lastTick = 0
local curRounded, maxRounded, sensRounded = nil, 0, nil
local curText, maxText, sensText = TXT_NO_DATA, "0", ""
local gaugeOk = false       -- device is a DS-24 II (R12)

local function resetSession()
  sensorSpd, shownSpd = nil, nil
  maxSpd, prevDistinct, distinctSince = 0, nil, 0
  everAboveHalf, everAboveLanding, belowLanding, aliveSaid = false, false, false, false
  stallArmed, overArmed = true, true
  lastSpokenSpd, lastSpokenAt = 0, nil
  lastTick = system.getTimeCounter()
  curRounded, maxRounded, sensRounded = nil, 0, nil
  curText, maxText, sensText = TXT_NO_DATA, "0", ""
end

local function resetMax()
  maxSpd, prevDistinct = 0, nil
  maxRounded, maxText = 0, "0"
end

------------------------------------------------------------------------------
-- Loop logic
------------------------------------------------------------------------------

-- Unassigned switch = off. "On" is above half travel (R10).
local function switchOn(item)
  if item == nil then
    return false
  end
  local v = system.getInputsVal(item)
  return v ~= nil and v > 0.5
end

-- Session max, filtered so a single-sample spike is ignored (R5): a value
-- counts once two distinct readings in a row reach it, or once it has held
-- for HOLD_MS (a steady speed). Also rebuilds the cached number strings, only
-- when their rounded value changes.
local function updateMax(now)
  local confirmed = nil
  if shownSpd ~= prevDistinct then
    if prevDistinct ~= nil then
      confirmed = math.min(prevDistinct, shownSpd)
    end
    prevDistinct = shownSpd
    distinctSince = now
  elseif now - distinctSince >= HOLD_MS then
    confirmed = shownSpd
  end
  if confirmed ~= nil and confirmed > maxSpd then
    maxSpd = confirmed
  end
  local r = math.floor(shownSpd + 0.5)
  if r ~= curRounded then
    curRounded = r
    curText = tostring(r)
  end
  r = math.floor(maxSpd + 0.5)
  if r ~= maxRounded then
    maxRounded = r
    maxText = tostring(r)
  end
  r = math.floor(sensorSpd + 0.5)
  if r ~= sensRounded then
    sensRounded = r
    sensText = tostring(r)
  end
end

-- Stall, overspeed and "airspeed alive" (data-model.md state transitions).
-- Stall uses sensor speed, overspeed uses shown speed (FR-011).
local function checkWarnings(anySwitch)
  if sensorSpd > cfg.vStall then
    stallArmed = true
  end
  if shownSpd <= cfg.vOver then
    overArmed = true
  end
  if not anySwitch then
    return
  end
  if stallArmed and everAboveLanding and sensorSpd <= cfg.vStall then
    stallArmed = false
    system.playFile(SND_STALL, AUDIO_IMMEDIATE)
    system.vibration(true, 4)
  end
  if overArmed and shownSpd > cfg.vOver then
    overArmed = false
    system.playFile(SND_OVER, AUDIO_IMMEDIATE)
    system.vibration(true, 3)
  end
  if everAboveHalf and not aliveSaid then
    aliveSaid = true
    system.playFile(SND_ALIVE, AUDIO_IMMEDIATE)
  end
end

-- Variable-interval callouts, formula from DFM v2.1 (R9).
local function checkCallout(now, onSw, contSw)
  if not (onSw or contSw) then
    return
  end
  if not (contSw or everAboveHalf) then
    return                  -- FR-009: silent until first above half landing speed
  end
  local interval
  if contSw or belowLanding then
    interval = cfg.tMin * 1000
  else
    local d = math.abs(shownSpd - lastSpokenSpd) / cfg.sens
    d = clamp(d, 0.5, 10)
    interval = math.min(cfg.tMin * 10000 / d, cfg.tMax * 1000)
  end
  -- Compare time differences only: the ms counter is a 32-bit integer that
  -- wraps and can be negative (seen in the emulator), so now - then is safe
  -- where now < then + interval is not.
  if (lastSpokenAt ~= nil and now - lastSpokenAt < interval) or system.isPlayback() then
    return
  end
  local n = math.floor(shownSpd + 0.5)
  lastSpokenSpd = n
  lastSpokenAt = now
  if cfg.numOnly == 1 or contSw or belowLanding or not everAboveLanding then
    system.playNumber(n, 0)
  else
    system.playNumber(n, 0, unitSpoken, "Speed")
  end
end

------------------------------------------------------------------------------
-- Settings form (contracts/settings-form.md)
------------------------------------------------------------------------------

local sensorLabels, sensorIds, sensorPars = {}, {}, {}
local notFoundIdx = 0
local idxGpsHint, idxDensOn, idxDensStatus, idxTemp = nil, nil, nil, nil
local idxAutoHint, idxOrder = nil, nil

local LABEL_W = 210
local CHECK_W = 270

-- Rebuilds the sensor list (late sensors appear, R4). Returns the selection.
local function buildSensorList()
  sensorLabels, sensorIds, sensorPars = { "(none)" }, { 0 }, { 0 }
  notFoundIdx = 0
  local selected = 1
  local parent = ""
  for _, s in ipairs(system.getSensors()) do
    if s.param == 0 then
      parent = s.label
    elseif s.type ~= 5 and s.type ~= 9 then
      local n = #sensorLabels + 1
      sensorLabels[n] = (parent ~= "") and (parent .. " / " .. s.label) or s.label
      sensorIds[n] = s.id
      sensorPars[n] = s.param
      if s.id == cfg.sId and s.param == cfg.sPar then
        selected = n
      end
    end
  end
  if cfg.sId ~= 0 and selected == 1 then
    local n = #sensorLabels + 1
    sensorLabels[n] = cfg.sLbl .. " (not found)"
    sensorIds[n] = cfg.sId
    sensorPars[n] = cfg.sPar
    notFoundIdx = n
    selected = n
  end
  return selected
end

local function heading(text)
  form.addRow(1)
  form.addLabel({ label = text, font = FONT_BOLD })
end

local function hint(text, visible)
  form.addRow(1)
  return form.addLabel({ label = text, font = FONT_MINI, visible = visible ~= false })
end

local function addInt(label, key, lo, hi, default, step, after, params)
  form.addRow(2)
  form.addLabel({ label = label, width = LABEL_W })
  return form.addIntbox(clamp(cfg[key], lo, hi), lo, hi, default, 0, step, function(value)
    save(key, value)
    if after then
      after()
    end
  end, params)
end

local function addCheck(label, key, after, params)
  form.addRow(2)
  form.addLabel({ label = label, width = CHECK_W })
  local idx
  idx = form.addCheckbox(cfg[key] == 1, function(value)
    -- The callback gets the old state; toggle it, as DFM v2.1 does.
    local on = not value
    if idx then
      form.setValue(idx, on)
    end
    save(key, on and 1 or 0)
    if after then
      after()
    end
  end, params)
  return idx
end

local function orderIsBad()
  return cfg.vStall >= cfg.vLand or cfg.vLand >= cfg.vOver
    or (cfg.fScale ~= 0 and cfg.vOver > cfg.fScale)
end

-- FR-026: flag, don't block, an illogical threshold order.
local function checkOrder()
  if idxOrder then
    form.setProperties(idxOrder, { visible = orderIsBad() })
  end
end

local function updateAutoHint()
  if idxAutoHint then
    local text = ""
    if cfg.fScale == 0 then
      text = "Auto: " .. fullScale
    end
    form.setProperties(idxAutoHint, { label = text })
  end
end

local function updateDensityRows()
  if idxDensStatus then
    local text = ""
    if cfg.sType == 2 then
      text = "Not used with GPS"
    elseif cfg.densOn == 1 then
      text = "Correction: " .. densPctText
    end
    form.setProperties(idxDensStatus, { label = text })
  end
  if idxDensOn then
    form.setProperties(idxDensOn, { enabled = cfg.sType == 1 })
  end
  if idxTemp then
    form.setProperties(idxTemp, { enabled = cfg.tStd ~= 1 })
  end
end

local function onThresholdChanged()
  recomputeScale()
  checkOrder()
  updateAutoHint()
end

local function onDensityChanged()
  recomputeDensity()
  recomputeScale()
  updateDensityRows()
end

-- Units change converts every unit-bearing setting (data-model.md).
local function onUnitsChanged(newUnits)
  local old = cfg.units
  if newUnits == old then
    return
  end
  local ratio = UNITS_MULT[newUnits] / UNITS_MULT[old]
  local function convert(key, lo, hi)
    save(key, clamp(math.floor(cfg[key] * ratio + 0.5), lo, hi))
  end
  convert("sens", 1, 100)
  convert("vLand", 0, 1000)
  convert("vStall", 0, 1000)
  convert("vOver", 0, 1000)
  if cfg.fScale ~= 0 then
    save("fScale", clamp(math.floor(cfg.fScale * ratio / 10 + 0.5) * 10, 10, 2000))
  end
  if UNITS_IMPERIAL[newUnits] ~= UNITS_IMPERIAL[old] then
    if UNITS_IMPERIAL[newUnits] then
      save("elev", clamp(math.floor(dens.mToFt(cfg.elev) / 10 + 0.5) * 10, -1000, 15000))
      save("temp", clamp(math.floor(dens.cToF(cfg.temp) + 0.5), -22, 122))
    else
      save("elev", clamp(math.floor(dens.ftToM(cfg.elev) / 10 + 0.5) * 10, -300, 4600))
      save("temp", clamp(math.floor(dens.fToC(cfg.temp) + 0.5), -30, 50))
    end
  end
  save("units", newUnits)
  recomputeAll()
  form.reinit(1)
end

local function initForm()
  local u = UNITS_TEXT[cfg.units]
  local imperial = UNITS_IMPERIAL[cfg.units]

  -- Sensor and switches
  heading("Sensor and switches")
  form.addRow(2)
  form.addLabel({ label = "Speed sensor", width = 120 })
  local selected = buildSensorList()   -- rebuilds sensorLabels; call before passing it
  form.addSelectbox(sensorLabels, selected, true, function(i)
    save("sId", sensorIds[i])
    save("sPar", sensorPars[i])
    if i == 1 then
      save("sLbl", "")
    elseif i ~= notFoundIdx then
      save("sLbl", string.sub(sensorLabels[i], 1, 63))
    end
  end, { width = 200 })

  form.addRow(2)
  form.addLabel({ label = "Sensor type", width = LABEL_W })
  form.addSelectbox({ "Airspeed (pitot)", "GPS" }, cfg.sType, false, function(i)
    save("sType", i)
    onDensityChanged()
    if idxGpsHint then
      form.setProperties(idxGpsHint, { visible = i == 2 })
    end
  end)
  idxGpsHint = hint("GPS: warnings use ground speed, wind shifts them", cfg.sType == 2)

  form.addRow(2)
  form.addLabel({ label = "Units", width = LABEL_W })
  form.addSelectbox(UNITS_TEXT, cfg.units, false, onUnitsChanged)

  addInt("Sensor calibration (%)", "cal", 1, 200, 100, 1, recomputeSensor)
  hint("100 = unchanged")

  form.addRow(2)
  form.addLabel({ label = "Callouts on/off switch", width = LABEL_W })
  form.addInputbox(cfg.swOn, true, function(v) save("swOn", v) end)
  form.addRow(2)
  form.addLabel({ label = "Continuous callouts switch", width = LABEL_W })
  form.addInputbox(cfg.swCont, true, function(v) save("swCont", v) end)

  -- Callouts
  heading("Callouts")
  addInt("Callout sensitivity (" .. u .. " change)", "sens", 1, 100, 10, 1)
  hint("Speak sooner when speed changes by this much")
  addInt("Shortest time between callouts (s)", "tMin", 1, 10, 2, 1)
  addInt("Longest time between callouts (s)", "tMax", 10, 60, 40, 1)
  addInt("Landing speed (" .. u .. ")", "vLand", 0, 1000, 60, 1, onThresholdChanged)
  hint("Callouts every shortest time below this")
  addCheck("Speak number only (no units)", "numOnly")
  addCheck("Announce stall speed at startup", "startAnn")

  -- Warnings
  heading("Warnings")
  idxOrder = hint("Check: stall < landing < overspeed < full scale", false)
  addInt("Stall warning at (" .. u .. ")", "vStall", 0, 1000, 45, 1, onThresholdChanged)
  addInt("Overspeed warning at (" .. u .. ")", "vOver", 0, 1000, 200, 1, onThresholdChanged)

  -- Air density
  heading("Air density")
  idxDensOn = addCheck("Correct for air density", "densOn", onDensityChanged,
    { enabled = cfg.sType == 1 })
  idxDensStatus = hint("")
  if imperial then
    addInt("Field elevation (ft)", "elev", -1000, 15000, 0, 10, onDensityChanged)
    idxTemp = addInt("Temperature (°F)", "temp", -22, 122, 59, 1, onDensityChanged,
      { enabled = cfg.tStd ~= 1 })
  else
    addInt("Field elevation (m)", "elev", -300, 4600, 0, 10, onDensityChanged)
    idxTemp = addInt("Temperature (°C)", "temp", -30, 50, 15, 1, onDensityChanged,
      { enabled = cfg.tStd ~= 1 })
  end
  addCheck("Use standard temperature", "tStd", onDensityChanged)
  hint("Leave correction off if your sensor already corrects for air density")

  -- Gauge
  heading("Gauge")
  addInt("Gauge full scale (" .. u .. ", 0 = auto)", "fScale", 0, 2000, 0, 10, onThresholdChanged)
  idxAutoHint = hint("")
  form.addRow(2)
  form.addLabel({ label = "Current speed color", width = LABEL_W })
  form.addSelectbox(COLOR_NAMES, cfg.colCur, false, function(i) save("colCur", i) end)
  form.addRow(2)
  form.addLabel({ label = "Max speed color", width = LABEL_W })
  form.addSelectbox(COLOR_NAMES, cfg.colMax, false, function(i) save("colMax", i) end)
  form.addRow(1)
  form.addLink(resetMax, { label = "Reset max speed" })

  form.addRow(1)
  form.addLabel({ label = APP_NAME .. " " .. APP_VERSION .. " - Based on DFM Speed Announcer by Dave McQueeney",
    font = FONT_MINI, alignRight = true })

  checkOrder()
  updateAutoHint()
  updateDensityRows()
end

local function keyForm()
end

------------------------------------------------------------------------------
-- Telemetry windows (contracts/telemetry-window.md). The only place lcd is used.
------------------------------------------------------------------------------

local roundDial, compactDial, faceCircle = nil, nil, nil
local rend = nil            -- one renderer, created lazily and reused (R6)

-- One layout cache per layout, rebuilt when the window size or scale changes.
local layCompact = { w = 0 }
local layRound = { w = 0 }
local layFull = { w = 0 }

local function setColor(c)
  lcd.setColor(c[1], c[2], c[3])
end

local function round(v)
  return math.floor(v + 0.5)
end

-- Largest of the given fonts where sample text fits in maxW x maxH.
local function fitFont(fonts, sample, maxW, maxH)
  for i = 1, #fonts do
    local f = fonts[i]
    if lcd.getTextWidth(f, sample) <= maxW and lcd.getTextHeight(f) <= maxH then
      return f
    end
  end
  return fonts[#fonts]
end

local NUM_FONTS = { FONT_MAXI, FONT_BIG, FONT_NORMAL, FONT_MINI }

-- Tick end points and label positions for a dial layout.
local function buildScale(L, dial, minorPer, withLabels)
  local mx1, my1, mx2, my2 = {}, {}, {}, {}
  local nx1, ny1, nx2, ny2 = {}, {}, {}, {}
  local lx, ly = {}, {}
  local font = L.labelFont
  local hLabel = lcd.getTextHeight(font)
  local rOut, rMaj, rMin = L.tickOut, L.tickOut - L.majorLen, L.tickOut - L.minorLen
  for i = 1, #scaleLabels do
    local v = (i - 1) * scaleStep
    local c, s = gauge.point(dial, v / fullScale)
    mx1[i], my1[i] = round(L.cx + c * rOut), round(L.cy + s * rOut)
    mx2[i], my2[i] = round(L.cx + c * rMaj), round(L.cy + s * rMaj)
    if withLabels then
      local tw = lcd.getTextWidth(font, scaleLabels[i])
      lx[i] = round(L.cx + c * L.labelR - tw / 2)
      ly[i] = round(L.cy + s * L.labelR - hLabel / 2)
    end
    for m = 1, minorPer do
      local f = (v + scaleStep * m / (minorPer + 1)) / fullScale
      if f < 1 then
        c, s = gauge.point(dial, f)
        local k = #nx1 + 1
        nx1[k], ny1[k] = round(L.cx + c * rOut), round(L.cy + s * rOut)
        nx2[k], ny2[k] = round(L.cx + c * rMin), round(L.cy + s * rMin)
      end
    end
  end
  L.mx1, L.my1, L.mx2, L.my2 = mx1, my1, mx2, my2
  L.nx1, L.ny1, L.nx2, L.ny2 = nx1, ny1, nx2, ny2
  L.lx, L.ly = lx, ly
  L.labels = withLabels
end

local function buildRound(L, w, h)
  local R = math.floor(math.min((h - 6) / 1.707, w / 2 - 20))
  L.R, L.cx = R, w // 2
  L.cy = math.floor((h - R * 1.707) / 2 + R)
  L.arcR, L.arcW, L.markW = R - 4, 6, 4
  L.glowStep, L.glowN = 3, 6
  L.tickOut, L.majorLen, L.minorLen = R - 9, 6, 3
  L.labelR = R - 22
  L.labelFont, L.unitFont = FONT_MINI, FONT_MINI
  buildScale(L, roundDial, 1, true)
  L.numFont = fitFont(NUM_FONTS, "888", R, R // 2)
  L.hNum, L.hMini = lcd.getTextHeight(L.numFont), lcd.getTextHeight(FONT_MINI)
  L.hNorm = lcd.getTextHeight(FONT_NORMAL)
end

local function buildFull(L, w, h)
  local R = math.floor(math.min((h - 8) / 1.707, (w - 100) / 2 - 4))
  L.R, L.cx = R, 4 + R
  L.cy = math.floor((h - R * 1.707) / 2 + R)
  L.arcR, L.arcW, L.markW = R - 5, 8, 5
  L.glowStep, L.glowN = 4, 8
  L.tickOut, L.majorLen, L.minorLen = R - 12, 10, 5
  L.labelR = R - 36
  L.labelFont, L.unitFont = FONT_NORMAL, FONT_NORMAL   -- larger text on the big dial
  buildScale(L, roundDial, 4, true)
  L.numFont = fitFont(NUM_FONTS, "888", R, R // 2)
  L.hNum, L.hMini = lcd.getTextHeight(L.numFont), lcd.getTextHeight(FONT_MINI)
  L.panelX = 2 * R + 16
  L.hBig = lcd.getTextHeight(FONT_BIG)
  -- Five panel rows spread over the visible height, capped so they don't
  -- drift too far apart.
  L.rowH = math.min((h - 8) // 5, L.hMini + L.hBig + 14)
  -- MAX sits in the open bottom of the dial, centered under the speed.
  L.maxValY = h - L.hBig - 4
  L.maxLabelY = L.maxValY - L.hMini
end

-- Single window: only about 157 x 34 is visible. Half-circle arc on the left
-- with the unit inside it, current speed in the middle, MAX column on the right.
local function buildCompact(L, w, h)
  local R = math.min(h - 3, (w - 90) // 2)
  L.R, L.cx, L.cy = R, 2 + R, h - 2
  L.arcR, L.arcW, L.markW = R - 3, 5, 3
  L.glowStep, L.glowN = 2, 5
  L.hMini = lcd.getTextHeight(FONT_MINI)
  L.maxW = math.max(lcd.getTextWidth(FONT_MINI, TXT_MAX), lcd.getTextWidth(FONT_MINI, "888"))
  L.maxX = w - L.maxW - 2
  L.numX = 2 * R + 8
  L.numFont = fitFont(NUM_FONTS, "888", L.maxX - L.numX - 4, h)
  L.hNum = lcd.getTextHeight(L.numFont)
  L.numY = (h - L.hNum) // 2
  L.maxY = (h - 2 * L.hMini) // 2
end

local function layoutFor(L, w, h, build)
  if L.w ~= w or L.h ~= h or L.ver ~= scaleVer then
    build(L, w, h)
    L.w, L.h, L.ver = w, h, scaleVer
  end
  return L
end

local function drawScale(L)
  setColor(C_MINOR)
  for k = 1, #L.nx1 do
    lcd.drawLine(L.nx1[k], L.ny1[k], L.nx2[k], L.ny2[k])
  end
  setColor(C_SCALE)
  for i = 1, #L.mx1 do
    lcd.drawLine(L.mx1[i], L.my1[i], L.mx2[i], L.my2[i])
    if L.labels then
      lcd.drawText(L.lx[i], L.ly[i], scaleLabels[i], L.labelFont)
    end
  end
end

-- Glow inside an arc from f0 to f1 in the current color: bands fading toward
-- the dial center, as in the reference image.
local function drawGlow(L, dial, f0, f1)
  local step = L.glowStep
  local r0 = L.arcR - L.arcW // 2 - step // 2
  for i = 1, L.glowN do
    gauge.arc(rend, dial, L.cx, L.cy, r0 - (i - 1) * step, f0, f1, step + 1, GLOW_ALPHA[i])
  end
end

-- Track, overspeed zone, marks, value arc and max marker (R6 draw order).
local function drawArcs(L, dial, showMarks)
  local cx, cy, arcR = L.cx, L.cy, L.arcR
  setColor(C_TRACK)
  gauge.arc(rend, dial, cx, cy, arcR, 0, 1, 3)
  setColor(C_ZONE)
  drawGlow(L, dial, fOver, 1)
  gauge.arc(rend, dial, cx, cy, arcR, fOver, 1, 4)
  if showMarks then
    setColor(C_SCALE)
    gauge.tick(dial, cx, cy, L.R - 1, arcR - 4, fStall)
    gauge.tick(dial, cx, cy, L.R - 1, arcR - 4, fLand)
  end
  if shownSpd ~= nil then
    local f = shownSpd / fullScale
    -- Up to the overspeed mark in the current-speed color; past it the arc
    -- (and its glow) switch to the overspeed color. Glow first, so the solid
    -- arc sits on top of its brightest band.
    local fBelow = math.min(f, fOver)
    setColor(COLORS[cfg.colCur])
    drawGlow(L, dial, 0, fBelow)
    gauge.arc(rend, dial, cx, cy, arcR, 0, fBelow, L.arcW)
    if f > fOver then
      setColor(C_ZONE)
      drawGlow(L, dial, fOver, f)
      gauge.arc(rend, dial, cx, cy, arcR, fOver, f, L.arcW)
    end
    setColor(C_TEXT)
    gauge.mark(rend, dial, cx, cy, arcR - L.arcW, arcR + 2, f, 2)
  end
  if maxSpd > 0 then
    setColor(COLORS[cfg.colMax])
    -- Thick and long enough to stand out: from inside the value arc to the rim.
    gauge.mark(rend, dial, cx, cy, arcR - L.arcW - 4, L.R, maxSpd / fullScale, L.markW)
  end
end

-- Label (small, grey) over value (white or colored), with an optional small
-- unit after the value.
local function drawRow(x, y, label, value, valueFont, valueColor, hLabel, unit)
  setColor(C_MINOR)
  lcd.drawText(x, y, label, FONT_MINI)
  setColor(valueColor)
  lcd.drawText(x, y + hLabel, value, valueFont)
  if unit then
    setColor(C_MINOR)
    -- Bottom-align the small unit with the value (the label is FONT_MINI too).
    local vx = x + lcd.getTextWidth(valueFont, value) + 2
    lcd.drawText(vx, y + lcd.getTextHeight(valueFont), unit, FONT_MINI)
  end
end

local function drawCenter(L)
  setColor(C_TEXT)
  local tw = lcd.getTextWidth(L.numFont, curText)
  lcd.drawText(L.cx - tw // 2, L.cy - L.hNum // 2 - 2, curText, L.numFont)
  setColor(C_SCALE)
  tw = lcd.getTextWidth(L.unitFont, unitText)
  lcd.drawText(L.cx - tw // 2, L.cy + L.hNum // 2, unitText, L.unitFont)
end

local function drawRound(w, h)
  local L = layoutFor(layRound, w, h, buildRound)
  setColor(C_BG)
  lcd.drawFilledRectangle(0, 0, w, h)
  setColor(C_FACE)
  gauge.face(rend, faceCircle, L.cx, L.cy, L.R, h - 1)
  drawArcs(L, roundDial, true)
  drawScale(L)
  drawCenter(L)
  -- Corner rows (FR-016): MAX top-left, STALL top-right, OVR bottom-right.
  local hM, hN = L.hMini, L.hNorm
  drawRow(1, 0, TXT_MAX, maxText, FONT_NORMAL, COLORS[cfg.colMax], hM, nil)
  local sw = math.max(lcd.getTextWidth(FONT_MINI, TXT_STALL), lcd.getTextWidth(FONT_NORMAL, stallText))
  drawRow(w - sw - 1, 0, TXT_STALL, stallText, FONT_NORMAL, C_TEXT, hM, nil)
  local ow = math.max(lcd.getTextWidth(FONT_MINI, TXT_OVR), lcd.getTextWidth(FONT_NORMAL, overText))
  drawRow(w - ow - 1, h - hM - hN, TXT_OVR, overText, FONT_NORMAL, C_TEXT, hM, nil)
end

local function drawFull(w, h)
  local L = layoutFor(layFull, w, h, buildFull)
  setColor(C_BG)
  lcd.drawFilledRectangle(0, 0, w, h)
  setColor(C_FACE)
  gauge.face(rend, faceCircle, L.cx, L.cy, L.R, h - 1)
  drawArcs(L, roundDial, true)
  drawScale(L)
  drawCenter(L)
  -- MAX in the open bottom of the dial: small label over the value, both
  -- centered under the center number (no unit; it's shown under the speed).
  setColor(C_MINOR)
  local tw = lcd.getTextWidth(FONT_MINI, TXT_MAX)
  lcd.drawText(L.cx - tw // 2, L.maxLabelY, TXT_MAX, FONT_MINI)
  setColor(COLORS[cfg.colMax])
  tw = lcd.getTextWidth(FONT_BIG, maxText)
  lcd.drawText(L.cx - tw // 2, L.maxValY, maxText, FONT_BIG)
  -- Side panel (spec US3 #2a). AIR DENSITY is always shown; ELEVATION and
  -- the uncorrected SENSOR speed only while correction is active.
  local x, y, rowH, hM = L.panelX, 4, L.rowH, L.hMini
  drawRow(x, y, TXT_STALL, stallText, FONT_BIG, C_TEXT, hM, unitText)
  drawRow(x, y + rowH, TXT_OVERSPEED, overText, FONT_BIG, C_TEXT, hM, unitText)
  drawRow(x, y + 2 * rowH, TXT_DENSITY, densRowText, FONT_BIG, C_TEXT, hM, nil)
  if densActive then
    drawRow(x, y + 3 * rowH, TXT_ELEVATION, elevText, FONT_BIG, C_TEXT, hM, elevUnitText)
    drawRow(x, y + 4 * rowH, TXT_SENSOR, sensText, FONT_BIG, C_TEXT, hM, unitText)
  end
end

local function drawCompact(w, h)
  local L = layoutFor(layCompact, w, h, buildCompact)
  setColor(C_FACE)
  lcd.drawFilledRectangle(0, 0, w, h)
  drawArcs(L, compactDial, L.R >= 30)
  setColor(C_TEXT)
  lcd.drawText(L.numX, L.numY, curText, L.numFont)
  setColor(C_SCALE)
  local tw = lcd.getTextWidth(FONT_MINI, unitText)
  lcd.drawText(L.cx - tw // 2, L.cy - L.hMini, unitText, FONT_MINI)
  setColor(C_MINOR)
  lcd.drawText(L.maxX, L.maxY, TXT_MAX, FONT_MINI)
  setColor(COLORS[cfg.colMax])
  lcd.drawText(L.maxX, L.maxY + L.hMini, maxText, FONT_MINI)
end

local function printGauge(w, h)
  if not gaugeOk then
    -- FR-013a: not a DS-24 II. Callouts and warnings still run in loop().
    local r, g, b = lcd.getFgColor()
    lcd.setColor(r, g, b)
    local tw = lcd.getTextWidth(FONT_MINI, TXT_NOTICE)
    lcd.drawText((w - tw) // 2, (h - lcd.getTextHeight(FONT_MINI)) // 2, TXT_NOTICE, FONT_MINI)
    return
  end
  if not rend then
    rend = lcd.renderer()
  end
  -- Pick the layout from the reported size, draw into the visible part.
  local vh = h - TITLE_H
  if h < 100 then
    drawCompact(w, vh)
  elseif w < 250 then
    drawRound(w, vh)
  else
    drawFull(w, vh)
  end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function init()
  loadSettings()
  recomputeAll()
  resetSession()

  roundDial = gauge.newDial(54, 225, 270)
  compactDial = gauge.newDial(36, 180, 180)
  faceCircle = gauge.newCircle(72)
  gaugeOk = string.find(system.getDeviceType() or "", "24 II", 1, true) ~= nil

  system.registerForm(1, MENU_APPS, APP_NAME, initForm, keyForm)
  system.registerTelemetry(1, APP_NAME, 0, printGauge)
  -- Size 4 (no status bar), as DFM-InsP uses: size 3 is covered by the desktop's
  -- model tile on the DS-24 II (emulator, 2026-09-27).
  system.registerTelemetry(2, APP_NAME, 4, printGauge)

  -- FR-028: tell the pilot the app is running and configured.
  if cfg.startAnn == 1 then
    if cfg.cal ~= 100 then
      system.playFile(SND_CAL, AUDIO_QUEUE)
      system.playNumber(cfg.cal, 0, "%")
    end
    system.playFile(SND_STALL_AT, AUDIO_QUEUE)
    system.playNumber(cfg.vStall, 0, unitSpoken)
  end
end

local function loop()
  local now = system.getTimeCounter()
  if now - lastTick < TICK_MS then
    return
  end
  lastTick = now

  -- Always call through system: Emulator Telemetry replaces it (R3).
  local s = nil
  if cfg.sId ~= 0 then
    s = system.getSensorValueByID(cfg.sId, cfg.sPar)
  end
  if s == nil or not s.valid then
    if sensorSpd ~= nil then
      sensorSpd, shownSpd = nil, nil
      curRounded, curText = nil, TXT_NO_DATA
      sensRounded, sensText = nil, TXT_NO_DATA
    end
    return                  -- no data: no flags, max, warnings or callouts
  end

  sensorSpd = s.value * kSensor
  shownSpd = sensorSpd * kDens

  -- Flight flags use sensor speed (FR-011).
  if sensorSpd > cfg.vLand / 2 then
    everAboveHalf = true
  end
  if sensorSpd > cfg.vLand then
    everAboveLanding = true
    belowLanding = false
  elseif everAboveLanding then
    belowLanding = true
  end

  local onSw, contSw = switchOn(cfg.swOn), switchOn(cfg.swCont)
  updateMax(now)
  checkWarnings(onSw or contSw)
  checkCallout(now, onSw, contSw)
end

local function destroy()
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
