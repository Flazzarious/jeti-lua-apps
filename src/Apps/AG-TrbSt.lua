-- AG-TrbSt.lua — Turbine Throttle Setup: guides the JETI turbine throttle setup and verifies the throttle output.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Read-and-instruct only: it reads the throttle output, the throttle stick
-- and the safety switch, and opens transmitter menus for the pilot. It never
-- changes a setting and never drives an output (constitution principle I,
-- FR-021). Nothing at flight time depends on it; the pilot removes it from
-- the model once the setup has passed (FR-022).
--
-- Design: specs/002-turbine-throttle-setup/ (plan.md, research.md,
-- data-model.md, contracts/). Research decisions are cited as R1..R13.

local APP_NAME = "Turbine Throttle Setup"
local APP_VERSION = "0.1.0"

-- Output reading -> pulse width, and percent -> pulse width (R1, R2).
local US_CENTER = 1500
local US_PER_UNIT = 500     -- getInputs("O<n>") returns -1..1
local US_PER_PCT = 5        -- 1% of servo travel = 5 us

-- Transmitter menus opened with system.openExternal (R3, API v1.5 p. 74-75).
local MENU = { servo = ":servoSetup", other = ":otherProps", dev = ":devExplorer" }

-- Screens (subforms, contracts/screens.md) and saved result states (data-model.md).
local SCR = { HOME = 1, INPUTS = 2, GUIDE = 3, VERIFY = 4, FAILSAFE = 5, SUMMARY = 6 }
local RES = { NONE = 0, PASSED = 1, COMPLETE = 2 }

-- Verify thresholds (contracts/verify.md), tuned on the bench.
local V = {
  SW_BAND = 0.5,            -- |switch| at or above this is a position, below is "middle"
  END_BAND = 0.95,          -- |stick| at or above this is the end of its travel
  STEADY_MS = 500,
  STICK_JITTER = 0.01,
  OUT_JITTER_US = 2,
  SAMPLE_N = 10,
  SAMPLE_MS = 50,
  LABEL_MS = 200,           -- live labels refresh at most this often
}

------------------------------------------------------------------------------
-- Settings (persisted per model; data-model.md). Integers, SwitchItems and
-- one integer array only (constitution IV).
------------------------------------------------------------------------------

local KEYS = {
  "sw", "offSg", "stk", "idlSg", "out", "tCut", "tIdle", "tFull", "tol",
  "scr", "gStep", "res", "meas", "when",
}  -- 14 keys (limit 30)
local DEFAULTS = {
  offSg = 0, idlSg = 0, out = 0, tCut = 1000, tIdle = 1200, tFull = 1900, tol = 10,
  scr = SCR.HOME, gStep = 1, res = RES.NONE, when = 0,
}  -- sw, stk and meas default to nil
local RANGES = {
  offSg = { -1, 1 }, idlSg = { -1, 1 }, out = { 0, 24 }, tol = { 5, 25 },
  scr = { 1, 6 }, gStep = { 1, 5 }, res = { 0, 2 },
}

local cfg = {}

local function save(key, value)
  cfg[key] = value
  system.pSave(key, value)
end

------------------------------------------------------------------------------
-- Settings math (contracts/settings-math.md). Each rule lives in one place.
------------------------------------------------------------------------------

local function toUs(v)
  return math.floor(US_CENTER + US_PER_UNIT * v + 0.5)
end

-- Travel -, Travel +, Throttle Cut output value and idle offset, in percent,
-- that produce the targets (R2; confirmed on two models). Targets are
-- multiples of 5, so every result is a whole percent.
local function settingsFor(cut, idle, full)
  return (US_CENTER - cut) // US_PER_PCT, (full - US_CENTER) // US_PER_PCT, -100,
    (idle - cut) // US_PER_PCT
end

-- Idle position in tenths of a percent, rounded: (idle - cut) / (full - cut).
local function idleTenths(cut, idle, full)
  local span = full - cut
  return (1000 * (idle - cut) + span // 2) // span
end

local function tenthsText(t)
  return string.format("%d.%d%%", t // 10, t % 10)
end

local function idlePosText(cut, idle, full)
  return "Idle position: " .. tenthsText(idleTenths(cut, idle, full))
end

-- Returns ok, line1, line2. When ok, the lines are the ECU warning or "".
-- Integer arithmetic only, so exactly 10% and 30% are exact (data-model.md).
local function validateTargets(cut, idle, full)
  if cut < 900 or idle < 900 or full < 900 or cut > 2100 or idle > 2100 or full > 2100 then
    return false, "Targets must be 900-2100 us", ""
  end
  if cut >= US_CENTER then
    return false, "Cut must be below 1500 us", ""
  end
  if full <= US_CENTER then
    return false, "Full must be above 1500 us", ""
  end
  if not (cut < idle and idle < full) then
    return false, "Need cut < idle < full", ""
  end
  local gap, span = idle - cut, full - cut
  if 10 * gap < span then
    return false, "Idle too close to cut:", "ECU may not tell run from stop"
  end
  if 10 * gap > 3 * span then
    return false, "Idle too high: over 30%", "of the cut-full range"
  end
  if 100 * gap < 15 * span then
    return true, "Idle at " .. tenthsText(idleTenths(cut, idle, full)) .. " of range.",
      "Some ECUs (e.g. Xicoy) want 15%+"
  end
  return true, "", ""
end

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  elseif v > hi then
    return hi
  end
  return v
end

local function loadSettings()
  for _, key in ipairs(KEYS) do
    cfg[key] = system.pLoad(key, DEFAULTS[key])
  end
  for key, r in pairs(RANGES) do
    local v = clamp(cfg[key], r[1], r[2])
    if v ~= cfg[key] then
      save(key, DEFAULTS[key])
    end
  end
  if not validateTargets(cfg.tCut, cfg.tIdle, cfg.tFull) then
    save("tCut", DEFAULTS.tCut)
    save("tIdle", DEFAULTS.tIdle)
    save("tFull", DEFAULTS.tFull)
  end
end

------------------------------------------------------------------------------
-- Live readouts (Setup inputs screen)
------------------------------------------------------------------------------

local OUT_NAMES = { "--" }  -- selectbox values: "--", "O1".."O24" (index = out + 1)
for i = 1, 24 do
  OUT_NAMES[i + 1] = "O" .. i
end

local live = {
  at = 0,                   -- last label refresh (getTimeCounter)
  outCode = nil,            -- "O<n>" for the chosen output, rebuilt when out changes
  swText = nil, stkText = nil, us = nil,   -- last shown values, to update on change only
}

local function refreshOutCode()
  live.outCode = cfg.out > 0 and OUT_NAMES[cfg.out + 1] or nil
  live.us = nil
end

local function readSwitch()
  if cfg.sw == nil then
    return nil
  end
  return system.getInputsVal(cfg.sw)
end

local function readStick()
  if cfg.stk == nil then
    return nil
  end
  return system.getInputsVal(cfg.stk)
end

local function readOut()
  if live.outCode == nil then
    return nil
  end
  return system.getInputs(live.outCode)
end

local function switchText(v)
  if v == nil then
    return "--"
  elseif cfg.offSg == 0 then
    return "not learned"
  elseif v * cfg.offSg >= V.SW_BAND then
    return "OFF"
  elseif v * cfg.offSg <= -V.SW_BAND then
    return "RUN"
  end
  return "middle"
end

local function stickText(v)
  if v == nil then
    return "--"
  elseif cfg.idlSg == 0 then
    return "not learned"
  elseif v * cfg.idlSg >= V.END_BAND then
    return "idle"
  elseif v * cfg.idlSg <= -V.END_BAND then
    return "full"
  end
  return "middle"
end

------------------------------------------------------------------------------
-- Form (contracts/screens.md)
------------------------------------------------------------------------------

local formOpen = false      -- loop may touch form rows only while true (R9)
local cur = SCR.HOME        -- screen the form shows
local idx = {}              -- component indices of rows updated after creation
local pend = {}             -- target values being edited, saved once valid

local LABEL_W = 170

local function hint(text, visible)
  form.addRow(1)
  return form.addLabel({ label = text, font = FONT_MINI, visible = visible ~= false })
end

local function goTo(screen)
  cur = screen
  save("scr", screen)
  form.reinit(screen)
end

local function canOpenMenus()
  return system.openExternal ~= nil
end

local function setMsg(line1, line2)
  if idx.msg1 then
    form.setProperties(idx.msg1, { label = line1, visible = line1 ~= "" })
    form.setProperties(idx.msg2, { label = line2, visible = line2 ~= "" })
  end
end

-- Placeholder for FR-005a (T028): ask before a change clears a saved result.
local function allowChange()
  return true
end

-- A target box changed: save all three only when the set is valid.
local function onTarget(key, value)
  if not allowChange() then
    return
  end
  pend[key] = value
  local ok, l1, l2 = validateTargets(pend.tCut, pend.tIdle, pend.tFull)
  if ok then
    save("tCut", pend.tCut)
    save("tIdle", pend.tIdle)
    save("tFull", pend.tFull)
    form.setProperties(idx.pos, { label = idlePosText(pend.tCut, pend.tIdle, pend.tFull) })
  else
    form.setProperties(idx.pos, { label = "Idle position: --" })
  end
  setMsg(l1, l2)
end

local function addTarget(label, key)
  form.addRow(2)
  form.addLabel({ label = label, width = LABEL_W })
  form.addIntbox(cfg[key], 900, 2100, DEFAULTS[key], 0, 5, function(value)
    onTarget(key, value)
  end)
end

local function buildInputs()
  form.setTitle("Setup inputs")
  form.addRow(1)
  form.addLabel({ label = "ENGINE MUST NOT BE ABLE TO START", font = FONT_BOLD })
  hint("(fuel off or ECU unplugged)")

  form.addRow(2)
  form.addLabel({ label = "Safety switch", width = LABEL_W })
  form.addInputbox(cfg.sw, false, function(v)
    if not allowChange() then
      return
    end
    save("sw", v)
    save("offSg", 0)          -- a new switch must be learned again (R5)
  end)
  form.addRow(2)
  form.addLabel({ label = "  Position", width = LABEL_W })
  idx.sw = form.addLabel({ label = "--", alignRight = true })

  form.addRow(2)
  form.addLabel({ label = "Throttle stick", width = LABEL_W })
  form.addInputbox(cfg.stk, true, function(v)
    if not allowChange() then
      return
    end
    save("stk", v)
    save("idlSg", 0)
  end)
  form.addRow(2)
  form.addLabel({ label = "  Position", width = LABEL_W })
  idx.stk = form.addLabel({ label = "--", alignRight = true })

  hint("Switch to OFF, stick to idle, press Learn.")
  idx.learn = hint("", false)

  form.addRow(2)
  form.addLabel({ label = "Throttle output", width = LABEL_W })
  form.addSelectbox(OUT_NAMES, cfg.out + 1, false, function(i)
    if not allowChange() then
      return
    end
    save("out", i - 1)
    refreshOutCode()
  end)
  form.addRow(2)
  form.addLabel({ label = "  Output now", width = LABEL_W })
  idx.us = form.addLabel({ label = "--", alignRight = true })

  pend.tCut, pend.tIdle, pend.tFull = cfg.tCut, cfg.tIdle, cfg.tFull
  addTarget("Cut target (us)", "tCut")
  addTarget("Idle target (us)", "tIdle")
  addTarget("Full target (us)", "tFull")
  form.addRow(1)
  idx.pos = form.addLabel({ label = idlePosText(cfg.tCut, cfg.tIdle, cfg.tFull) })
  idx.msg1 = hint("", false)
  idx.msg2 = hint("", false)
  local _, l1, l2 = validateTargets(cfg.tCut, cfg.tIdle, cfg.tFull)
  setMsg(l1, l2)

  form.addRow(2)
  form.addLabel({ label = "Tolerance (+/- us)", width = LABEL_W })
  form.addIntbox(cfg.tol, RANGES.tol[1], RANGES.tol[2], DEFAULTS.tol, 0, 1, function(value)
    if not allowChange() then
      return
    end
    save("tol", value)
  end)

  form.setButton(1, "Back", ENABLED)
  form.setButton(3, "Learn", ENABLED)
  -- Temporary, for calibration only (T008); removed in T013.
  if canOpenMenus() then
    form.setButton(2, "Servo", ENABLED)
    form.setButton(4, "Other", ENABLED)
  end

  live.at, live.swText, live.stkText, live.us = 0, nil, nil, nil
end

-- F3 on Setup inputs: store the OFF sign and the stick's idle sign (R5).
local function learn()
  local text
  local sv, kv = readSwitch(), readStick()
  if sv == nil or kv == nil then
    text = "Choose the switch and stick first."
  elseif math.abs(sv) < V.SW_BAND then
    text = "Use a two-position switch."
  elseif math.abs(kv) < V.END_BAND then
    text = "Move the stick fully to idle."
  elseif allowChange() then
    save("offSg", sv > 0 and 1 or -1)
    save("idlSg", kv > 0 and 1 or -1)
    text = "Learned: OFF and idle."
  else
    return
  end
  form.setProperties(idx.learn, { label = text, visible = true })
  live.swText, live.stkText = nil, nil
end

local function buildHome()
  form.setTitle(APP_NAME)
  form.addRow(1)
  form.addLink(function() goTo(SCR.INPUTS) end, { label = "Setup inputs" })
end

local function buildStub()
  form.setTitle(APP_NAME)
  hint("Not built yet.")
  form.setButton(1, "Back", ENABLED)
end

local BUILD = {
  [SCR.HOME] = buildHome,
  [SCR.INPUTS] = buildInputs,
  [SCR.GUIDE] = buildStub,
  [SCR.VERIFY] = buildStub,
  [SCR.FAILSAFE] = buildStub,
  [SCR.SUMMARY] = buildStub,
}

local function initForm()
  formOpen = true
  idx = {}
  BUILD[cur]()
end

local function onKey(keyCode)
  if keyCode == KEY_1 and cur ~= SCR.HOME then
    goTo(SCR.HOME)
  elseif cur == SCR.INPUTS then
    if keyCode == KEY_3 then
      learn()
    elseif keyCode == KEY_2 and canOpenMenus() then
      system.openExternal(MENU.servo)
    elseif keyCode == KEY_4 and canOpenMenus() then
      system.openExternal(MENU.other)
    end
  end
end

-- The form is gone: drop its indices so nothing calls form.* on them (R9).
local function closeForm()
  formOpen = false
  idx = {}
end

-- Live labels on Setup inputs, at most every LABEL_MS, only on change.
local function updateInputs(now)
  if now - live.at < V.LABEL_MS then
    return
  end
  live.at = now
  local t = switchText(readSwitch())
  if t ~= live.swText then
    live.swText = t
    form.setProperties(idx.sw, { label = t })
  end
  t = stickText(readStick())
  if t ~= live.stkText then
    live.stkText = t
    form.setProperties(idx.stk, { label = t })
  end
  local v = readOut()
  local us = v and toUs(v) or -1
  if us ~= live.us then
    live.us = us
    form.setProperties(idx.us, { label = us >= 0 and (us .. " us") or "--" })
  end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function init()
  loadSettings()
  refreshOutCode()
  cur = cfg.scr
  system.registerForm(1, MENU_APPS, APP_NAME, initForm, onKey, nil, closeForm)
end

local function loop()
  if not formOpen then
    return
  end
  if cur == SCR.INPUTS and idx.us then
    updateInputs(system.getTimeCounter())
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
