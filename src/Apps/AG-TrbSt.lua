-- AG-TrbSt.lua — Throttle Setup Wizard: guides the JETI turbine throttle setup and verifies the throttle output.
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

local APP_NAME = "Throttle Setup Wizard"
local APP_VERSION = "0.1.0"

-- Output reading -> pulse width (R1, confirmed on the transmitter).
local US_CENTER = 1500
local US_PER_UNIT = 500     -- getInputs("O<n>") returns -1..1

-- The one recommended setup (contracts/settings-math.md). Only the
-- Throttle-Cut output value depends on the ECU type: 1 Xicoy, 2 any other.
local REC = {
  MAX_NEG = -80, MAX_POS = 80, IDLE_OFS = 20,
  CUT_VAL = { -125, -100 },
  TARGETS = { { 1000, 1200, 1900 }, { 1100, 1200, 1900 } },  -- cut, idle, full (us)
}
local ECU_NAMES = { "--", "Xicoy", "Other" }  -- selectbox values (index = ecu + 1)

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
  "sw", "offSg", "stk", "idlSg", "out", "ecu", "tol",
  "scr", "gStep", "res", "meas", "when",
}  -- 12 keys (limit 30)
local DEFAULTS = {
  offSg = 0, idlSg = 0, out = 0, ecu = 0, tol = 10,
  scr = SCR.HOME, gStep = 1, res = RES.NONE, when = 0,
}  -- sw, stk and meas default to nil
local RANGES = {
  offSg = { -1, 1 }, idlSg = { -1, 1 }, out = { 0, 24 }, ecu = { 0, 2 }, tol = { 5, 25 },
  scr = { 1, 6 }, gStep = { 1, 5 }, res = { 0, 2 },
}

local cfg = {}

local function save(key, value)
  cfg[key] = value
  system.pSave(key, value)
end

------------------------------------------------------------------------------
-- Conversions (contracts/settings-math.md)
------------------------------------------------------------------------------

local function toUs(v)
  return math.floor(US_CENTER + US_PER_UNIT * v + 0.5)
end

local function targetsText(ecu)
  local t = REC.TARGETS[ecu]
  if t == nil then
    return "Targets: --"
  end
  return "Targets: " .. t[1] .. " / " .. t[2] .. " / " .. t[3] .. " us"
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
  swPct = nil, stkPct = nil,
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
    return "CUT"
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

local LABEL_W = 170

local function hint(text, visible)
  form.addRow(1)
  return form.addLabel({ label = text, font = FONT_MINI, visible = visible ~= false })
end

-- Always rebuild subform 1 and pick the screen from `cur`. Switching with
-- reinit(2) appeared to close the form in the emulator (6.04, 2026-10-10);
-- reinit(1) is what Speed Gauge uses.
local function goTo(screen)
  cur = screen
  save("scr", screen)
  form.reinit(1)
end

local function canOpenMenus()
  return system.openExternal ~= nil
end

-- Placeholder for FR-005a (T028): ask before a change clears a saved result.
local function allowChange()
  return true
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
  hint("Assign it as proportional (P).")
  form.addRow(2)
  form.addLabel({ label = "  Position", width = LABEL_W })
  idx.stk = form.addLabel({ label = "--", alignRight = true })

  hint("Switch to CUT and stick to")
  hint("idle (down), then press the")
  hint("Learn menu button.")
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
  hint("Output (O1-O24) the ECU's")
  hint("throttle lead is plugged into.")
  form.addRow(2)
  form.addLabel({ label = "  Signal now", width = LABEL_W })
  idx.us = form.addLabel({ label = "--", alignRight = true })
  hint("Pulse width the ECU gets now.")

  form.addRow(2)
  form.addLabel({ label = "ECU", width = LABEL_W })
  form.addSelectbox(ECU_NAMES, cfg.ecu + 1, false, function(i)
    if not allowChange() then
      return
    end
    save("ecu", i - 1)
    form.setProperties(idx.targets, { label = targetsText(cfg.ecu) })
  end)
  hint("Xicoy: cut -125%. Others: -100%.")
  form.addRow(1)
  idx.targets = form.addLabel({ label = targetsText(cfg.ecu) })

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

  live.at, live.swText, live.stkText, live.us, live.swPct, live.stkPct = 0, nil, nil, nil, nil, nil
end

-- The stick must be assigned as proportional, or it reads like a switch and
-- "middle" is never seen (transmitter, 2026-10-10). nil info is treated as OK.
local function stickIsProportional()
  local info = cfg.stk and system.getSwitchInfo(cfg.stk)
  return info == nil or info.proportional ~= false
end

-- F3 on Setup inputs: store the CUT sign and the stick's idle sign (R5).
local function learn()
  local text
  local sv, kv = readSwitch(), readStick()
  if sv == nil or kv == nil then
    text = "Choose the switch and stick first."
  elseif not stickIsProportional() then
    text = "Stick must be proportional (P)."
  elseif math.abs(sv) < V.SW_BAND then
    text = "Use a two-position switch."
  elseif math.abs(kv) < V.END_BAND then
    text = "Move the stick fully to idle."
  elseif allowChange() then
    save("offSg", sv > 0 and 1 or -1)
    save("idlSg", kv > 0 and 1 or -1)
    text = "Learned: CUT and idle."
  else
    return
  end
  form.setProperties(idx.learn, { label = text, visible = true })
  live.swText, live.stkText = nil, nil
end

local function buildHome()
  form.setTitle(APP_NAME)
  form.addRow(1)
  form.addLink(function()
    print("TrbSt link: Setup inputs")
    local ok, err = pcall(goTo, SCR.INPUTS)
    if not ok then
      print("TrbSt goTo error: " .. tostring(err))
    end
  end, { label = "Setup inputs" })
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

-- Show a Lua error on the form instead of losing the form (calibration aid).
local function showError(where, err)
  local text = where .. ": " .. tostring(err)
  print(text)
  for i = 1, #text, 32 do
    form.addRow(1)
    form.addLabel({ label = string.sub(text, i, i + 31), font = FONT_MINI })
  end
  form.setButton(1, "Back", ENABLED)
end

local function initForm(subformId)
  print("TrbSt build " .. cur .. " (subform " .. tostring(subformId) .. ")")
  formOpen = true
  idx = {}
  local ok, err = pcall(BUILD[cur])
  if not ok then
    idx = {}
    showError("build " .. cur, err)
  end
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
  print("TrbSt form closed on screen " .. cur)
  formOpen = false
  idx = {}
end

-- Live labels on Setup inputs, at most every LABEL_MS, only on change.
local function updateInputs(now)
  if now - live.at < V.LABEL_MS then
    return
  end
  live.at = now
  -- Word plus raw percent, e.g. "middle (+3%)"; rebuilt only when either changes.
  local v = readSwitch()
  local t, p = switchText(v), v and math.floor(v * 100 + 0.5) or 0
  if t ~= live.swText or p ~= live.swPct then
    live.swText, live.swPct = t, p
    form.setProperties(idx.sw, { label = v and string.format("%s (%+d%%)", t, p) or t })
  end
  v = readStick()
  t, p = stickText(v), v and math.floor(v * 100 + 0.5) or 0
  if t ~= live.stkText or p ~= live.stkPct then
    live.stkText, live.stkPct = t, p
    form.setProperties(idx.stk, { label = v and string.format("%s (%+d%%)", t, p) or t })
  end
  v = readOut()
  local us = v and toUs(v) or -1
  if us ~= live.us then
    live.us = us
    local text = "choose output"
    if us >= 0 then
      text = us .. " us"
    elseif live.outCode then
      text = "no signal"
    end
    form.setProperties(idx.us, { label = text })
  end
end

------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------

local function init()
  print("TrbSt keys: F1=" .. tostring(KEY_1) .. " F5=" .. tostring(KEY_5) .. " ENTER=" .. tostring(KEY_ENTER)
    .. " ESC=" .. tostring(KEY_ESC) .. " RELEASED=" .. tostring(KEY_RELEASED))
  loadSettings()
  refreshOutCode()
  cur = cfg.scr
  system.registerForm(1, MENU_APPS, APP_NAME, initForm, onKey, nil, closeForm)
end

local beatAt = 0             -- debug heartbeat (calibration build only)

local function loop()
  local now = system.getTimeCounter()
  if now - beatAt >= 2000 then
    beatAt = now
    print("TrbSt loop: formOpen=" .. tostring(formOpen) .. " cur=" .. cur .. " idx.us=" .. tostring(idx.us)
      .. " sw=" .. tostring(readSwitch()) .. " stk=" .. tostring(readStick()) .. " out=" .. tostring(readOut()))
  end
  if not formOpen then
    return
  end
  if cur == SCR.INPUTS and idx.us then
    local ok, err = pcall(updateInputs, system.getTimeCounter())
    if not ok then
      print("TrbSt loop: " .. tostring(err))
      if idx.learn then
        form.setProperties(idx.learn, { label = string.sub("ERR " .. tostring(err), 1, 60), visible = true })
      end
      idx.us = nil            -- stop retrying every loop
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
