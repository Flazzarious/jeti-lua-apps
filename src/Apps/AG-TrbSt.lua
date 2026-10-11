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
local MENU = { servo = ":servoSetup", other = ":otherProps", dev = ":devExplorer", sound = ":soundEvent" }

-- Screens (subforms, contracts/screens.md) and saved result states (data-model.md).
local SCR = { HOME = 1, INPUTS = 2, GUIDE = 3, VERIFY = 4, FAILSAFE = 5, SUMMARY = 6, VOICE = 7 }
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
  scr = { 1, 7 }, gStep = { 1, 5 }, res = { 0, 2 },
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

-- FR-005a: while a result is saved, the first change on Setup inputs asks
-- first. Yes clears the result; No rebuilds the screen from the saved
-- values, which undoes the edit in the form.
local inputsConfirmed = false   -- reset each time Setup inputs is built

local function allowChange()
  if cfg.res == RES.NONE or inputsConfirmed then
    return true
  end
  if form.question("Clear saved result?", "Changing setup means it must be",
      "verified again.") == 1 then
    inputsConfirmed = true
    save("res", RES.NONE)
    save("meas", nil)
    save("when", 0)
    return true
  end
  goTo(SCR.INPUTS)
  return false
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
  hint("Xicoy: Throttle-Cut -125%.")
  hint("Other: Throttle-Cut -100%.")
  hint("Tested with KingTech and Swiwin;")
  hint("should work with most others.")
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

  inputsConfirmed = false
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

------------------------------------------------------------------------------
-- Voice callouts (optional; spec User Story 4, research R14, R15). The app
-- never plays these: it copies them to /Audio for JETI's Sounds on event.
------------------------------------------------------------------------------

-- dest is the voice folder for the transmitter's language, e.g. /Audio/en:
-- that's where JETI's voice picker looks and where pilots keep their own
-- callouts (Aaron's transmitter, 2026-10-10). Set in init().
local VOICE = {
  src = "/Apps/AG-TrbSt", dest = "/Audio/en",
  files = { "TurbOff.wav", "TurbOn.wav" },
  CHUNK = 2048, CHUNKS_PER_LOOP = 4,      -- keeps each loop() call light (R15)
}
local vstate = { "no", "no" }             -- per file: "yes", "no", "copying...", "failed: <why>"
local vsrcOk = false                      -- both of the app's own files are present
---@class CopyJob
---@field list integer[]  indexes into VOICE.files still to copy
---@field k integer       position in list
---@field fin JetiFile|nil
---@field fout JetiFile|nil
---@field created boolean the destination was created by this copy
local job = nil ---@type CopyJob|nil  -- copy in progress (R15)

-- JETI Studio's io.open needs the path without its leading "/"; the
-- transmitter takes the absolute path (docs/jeti-api-notes.md).
local function openFile(path, mode)
  return io.open(path, mode) or io.open(string.sub(path, 2), mode)
end

local function removeFile(path)
  return io.remove(path) or io.remove(string.sub(path, 2))
end

local function fileExists(path)
  local f = openFile(path, "r")
  if f then
    io.close(f)
    return true
  end
  return false
end

-- Size from the folder listing; nil if the folder can't be listed.
local function fileSize(folder, name)
  local want = string.lower(name)
  for _, path in ipairs({ folder, string.sub(folder, 2) }) do
    local ok, size = pcall(function()
      for n, kind, sz in dir(path) do
        if kind == "file" and string.lower(n) == want then
          return sz
        end
      end
    end)
    if ok and size then
      return size
    end
  end
  return nil
end

-- Older firmware may lack io.remove (5.00+) or dir: no Copy there (R13).
local function canCopyHere()
  return io.remove ~= nil and dir ~= nil
end

local function canCopy()
  if job or not vsrcOk or not canCopyHere() then
    return false
  end
  for i = 1, #VOICE.files do
    if vstate[i] ~= "yes" then
      return true
    end
  end
  return false
end

-- Status labels and the Copy button, only while this screen is showing.
local function showVoice()
  if not formOpen or cur ~= SCR.VOICE or not idx.vs then
    return
  end
  for i = 1, #VOICE.files do
    form.setProperties(idx.vs[i], { label = vstate[i] })
  end
  form.setButton(2, "Copy", canCopy() and ENABLED or DISABLED)
end

local function scanVoice()
  vsrcOk = true
  for i, name in ipairs(VOICE.files) do
    if not fileExists(VOICE.src .. "/" .. name) then
      vsrcOk = false
    end
    if not (job and job.list[job.k] == i) and string.sub(vstate[i], 1, 6) ~= "failed" then
      vstate[i] = fileExists(VOICE.dest .. "/" .. name) and "yes" or "no"
    end
  end
end

-- Move on to the next file; the job ends after the last one.
---@param j CopyJob
local function nextFile(j)
  j.fin, j.fout, j.created = nil, nil, false
  j.k = j.k + 1
  if j.k > #j.list then
    job = nil
  end
  showVoice()
end

-- Close the file being copied and check it; on failure delete the partial
-- copy. `why` is nil on success, else the failed step for the status line.
---@param j CopyJob
---@param why string|nil
local function finishFile(j, why)
  local i = j.list[j.k]
  local name = VOICE.files[i]
  if j.fin then
    io.close(j.fin)
  end
  if j.fout then
    io.close(j.fout)
  end
  if not why then
    local got, want = fileSize(VOICE.dest, name), fileSize(VOICE.src, name)
    if got ~= want then
      why = "size " .. tostring(got) .. "/" .. tostring(want)
    end
  end
  if why and j.created then
    removeFile(VOICE.dest .. "/" .. name)
  end
  vstate[i] = why and ("failed: " .. why) or "yes"
  nextFile(j)
end

-- One loop() step of the copy: open the next file, or move a few chunks.
---@param j CopyJob
local function stepCopy(j)
  local i = j.list[j.k]
  local name = VOICE.files[i]
  if not j.fin then
    local dest = VOICE.dest .. "/" .. name
    if fileExists(dest) then            -- never overwrite (FR-027): keep it
      vstate[i] = "yes"
      nextFile(j)
      return
    end
    j.fin = openFile(VOICE.src .. "/" .. name, "r")
    if not j.fin then
      finishFile(j, "read")
      return
    end
    j.fout = openFile(dest, "w")
    j.created = j.fout ~= nil
    if not j.fout then
      finishFile(j, "create")
      return
    end
    vstate[i] = "copying..."
    showVoice()
  end
  for _ = 1, VOICE.CHUNKS_PER_LOOP do
    local data = io.read(j.fin, VOICE.CHUNK)
    if data == nil or data == "" then
      finishFile(j, nil)
      return
    end
    if not io.write(j.fout, data) then
      finishFile(j, "write")
      return
    end
  end
end

local function startCopy()
  local list = {}
  for i = 1, #VOICE.files do
    if vstate[i] ~= "yes" then
      vstate[i] = "no"
      list[#list + 1] = i
    end
  end
  if #list > 0 then
    job = { list = list, k = 1, created = false }
  end
  showVoice()
end

local function buildVoice()
  form.setTitle("Voice callouts")
  scanVoice()
  hint("Say 'Turbine off' at CUT and")
  hint("'Turbine on' at RUN, using the")
  hint("transmitter's Sounds on event.")
  hint("Voice folder: " .. VOICE.dest)
  idx.vs = {}
  for i, name in ipairs(VOICE.files) do
    form.addRow(2)
    form.addLabel({ label = name, width = 120 })
    idx.vs[i] = form.addLabel({ label = vstate[i], alignRight = true })
  end
  hint("Voice files not installed.", not vsrcOk)
  hint("Copy TurbOff.wav and TurbOn.wav", vsrcOk and not canCopyHere())
  hint("there with the PC.", vsrcOk and not canCopyHere())
  hint("Copy puts them in the voice")
  hint("folder above.")
  hint("Then press Open. In Sounds on")
  hint("Event press + twice: one line")
  hint("per switch position.")
  hint("1. Switch: move safety switch")
  hint("   to CUT. File: TURBOFF.WAV")
  hint("2. Switch: move it to RUN.")
  hint("   File: TURBON.WAV")
  hint("Keep any callouts you already")
  hint("have, or use your own files.")
  hint("Voice: Piper, Amy, CC BY-SA 4.0")
  form.setButton(1, "Back", ENABLED)
  form.setButton(2, "Copy", canCopy() and ENABLED or DISABLED)
  if canOpenMenus() then
    form.setButton(3, "Open", ENABLED)
  end
end

------------------------------------------------------------------------------
-- Shared helpers for Home, the guide, verify and the summary
------------------------------------------------------------------------------

-- Guided setup and verify need every input (data-model "Setup is complete").
local function setupComplete()
  return cfg.sw ~= nil and cfg.stk ~= nil and cfg.out > 0 and cfg.ecu > 0
    and cfg.offSg ~= 0 and cfg.idlSg ~= 0
end

local function fmtDate(n)
  return string.format("%04d-%02d-%02d", n // 10000, n // 100 % 100, n % 100)
end

-- Status as two short lines (data-model "Saved result").
local function statusLines()
  if cfg.res == RES.COMPLETE then
    return "Setup complete", "Verified " .. fmtDate(cfg.when)
  elseif cfg.res == RES.PASSED then
    return "Incomplete -", "failsafe not confirmed"
  end
  return "Not verified", ""
end

local function addStatus()
  local l1, l2 = statusLines()
  form.addRow(1)
  form.addLabel({ label = l1, font = FONT_BOLD })
  hint(l2, l2 ~= "")
end

------------------------------------------------------------------------------
-- Home (contracts/screens.md section 1)
------------------------------------------------------------------------------

local function buildHome()
  form.setTitle(APP_NAME)
  addStatus()
  local ready = setupComplete()
  form.addRow(1)
  form.addLink(function() goTo(SCR.INPUTS) end, { label = "Setup inputs" })
  form.addRow(1)
  form.addLink(function() goTo(SCR.GUIDE) end, { label = "Guided setup", enabled = ready })
  form.addRow(1)
  form.addLink(function() goTo(SCR.VERIFY) end, { label = "Verify", enabled = ready })
  form.addRow(1)
  form.addLink(function() goTo(SCR.SUMMARY) end, { label = "Summary", enabled = cfg.res > RES.NONE })
  form.addRow(1)
  form.addLink(function() goTo(SCR.VOICE) end, { label = "Voice callouts (optional)" })
  hint("Complete Setup inputs first.", not ready)
end

------------------------------------------------------------------------------
-- Guided setup (contracts/screens.md section 3): five steps, one per screen.
------------------------------------------------------------------------------

local GUIDE_MENU = { MENU.servo, MENU.other, MENU.other, MENU.dev }  -- step 5 has none

local function guideLines(step)
  if step == 1 then
    return { "Servo Setup > Servo No.:", "your throttle output." },
      { string.format("Max negative: %d%%", REC.MAX_NEG), string.format("Max positive: %d%%", REC.MAX_POS) },
      { "Leave the limits at -125/125%." }
  elseif step == 2 then
    local vals = { string.format("Throttle-Cut output value: %d%%", REC.CUT_VAL[cfg.ecu]) }
    if cfg.ecu == 1 then
      vals[2] = "(Xicoy)"
    end
    return { "Other Model Options >", "Throttle Cut", "Throttle-Cut switch: choose it",
      "and move the switch to CUT." }, vals, {}
  elseif step == 3 then
    return { "Other Model Options >", "Throttle Idle", "Throttle-Idle switch: same",
      "switch, moved to RUN." },
      { string.format("Throttle-Idle offset: %d%%", REC.IDLE_OFS) },
      { "Check: in RUN, Idle shows a", "tick and Cut a cross." }
  elseif step == 4 then
    return { "Device Explorer > receiver >", "Configuration > Fail-Safe:" },
      { "Fail-Safe: Enabled, 1.5s.", "Throttle OutPin mode: Out OFF." },
      { "Never Hold: the engine would", "stay at its last throttle.", "Test it by hand at the end." }
  end
  return { "Use a JETI 2-position locking", "switch: pull the lever to flip,",
    "so it can't be bumped." }, {}, { "Fit it within easy reach.", "Don't use it for anything else.",
    "Optional: Voice callouts (Home)." }
end

local function buildGuide()
  local step = cfg.gStep
  form.setTitle(string.format("Step %d of 5", step))
  local before, values, after = guideLines(step)
  for _, s in ipairs(before) do
    hint(s)
  end
  for _, s in ipairs(values) do
    form.addRow(1)
    form.addLabel({ label = s, font = FONT_BOLD })
  end
  for _, s in ipairs(after) do
    hint(s)
  end
  form.setButton(1, "Back", ENABLED)
  if GUIDE_MENU[step] and canOpenMenus() then
    form.setButton(3, "Open", ENABLED)
  end
  form.setButton(5, step < 5 and "Next" or "Verify", ENABLED)
end

local function guideKey(keyCode)
  local step = cfg.gStep
  if keyCode == KEY_1 then
    if step > 1 then
      save("gStep", step - 1)
      goTo(SCR.GUIDE)
    else
      goTo(SCR.HOME)
    end
  elseif keyCode == KEY_3 and GUIDE_MENU[step] and canOpenMenus() then
    system.openExternal(GUIDE_MENU[step])
  elseif keyCode == KEY_5 then
    if step < 5 then
      save("gStep", step + 1)
      goTo(SCR.GUIDE)
    else
      goTo(SCR.VERIFY)
    end
  end
end

------------------------------------------------------------------------------
-- Verify (contracts/verify.md; research R7, R8). Session only, never saved
-- until a clean run passes.
------------------------------------------------------------------------------

local PH = { IDLE = 1, CHECK = 2, WAIT = 3, SETTLE = 4, SAMPLE = 5, FAILED = 6, PASSED = 7 }
-- What each test needs, shown on its "Test" and "Set" lines (screen layout:
-- Test / Set / Now / Do, so the pilot sees the question apart from the
-- live switch and stick positions; Aaron, 2026-10-10).
local SW_CUT = "Switch: CUT (engine off)"
local SW_RUN = "Switch: RUN (not cut)"
local STATES = {   -- t: index into REC.TARGETS[ecu] (1 cut, 2 idle, 3 full)
  { name = "Cut", cut = true, idle = true, t = 1, test = "1 of 4: Cut", set1 = SW_CUT, set2 = "Stick: IDLE (down)" },
  { name = "Cut override", cut = true, idle = false, t = 1, test = "2 of 4: Cut override", set1 = SW_CUT, set2 = "Stick: FULL (up)" },
  { name = "Idle", cut = false, idle = true, t = 2, test = "3 of 4: Idle", set1 = SW_RUN, set2 = "Stick: IDLE (down)" },
  { name = "Full", cut = false, idle = false, t = 3, test = "4 of 4: Full", set1 = SW_RUN, set2 = "Stick: FULL (up)" },
}
local CHECK_INFO = { test = "Output check", set1 = SW_RUN, set2 = "Stick: IDLE (down), then FULL" }
local READY_INFO = { test = "Ready", set1 = "Checks the throttle in each", set2 = "switch and stick position." }

-- "Do" lines: two constant strings each, never built per loop.
local DO = {
  start = { "Press Start to begin.", "" },
  toCut = { "Safety switch to CUT", "(cut: engine off)" },
  toRun = { "Safety switch to RUN", "(not cut: engine may run)" },
  toIdle = { "Move the stick fully DOWN", "(idle) and hold it there." },
  toFull = { "Move the stick fully UP", "(full) and hold it there." },
  checkFull = { "Now move the stick fully UP", "(full)." },
  steady = { "Hold still...", "" },
  measuring = { "Measuring...", "" },
  inputs = { "Check Setup inputs.", "" },
  passed = { "All four passed.", "Press Next." },
  retried = { "All passed after a retry.", "Restart for a clean run." },
  failed = { "Failed: reason below.", "Fix it, then press Retry." },
}

local run = { phase = PH.IDLE, k = 0, retried = false, m = {}, row = {}, why1 = "", why2 = "" }

local function near(x, t)
  return math.abs(x - t) <= math.max(cfg.tol, 15)
end

-- Switch and stick positions (contracts/verify.md "Position and steadiness").
local function switchIs(cut, sv)
  local s = sv * cfg.offSg
  if cut then
    return s >= V.SW_BAND
  end
  return s <= -V.SW_BAND
end

local function stickAt(idle, kv)
  local s = kv * cfg.idlSg
  if idle then
    return s >= V.END_BAND
  end
  return s <= -V.END_BAND
end

local function resultRow(k)
  local tg = REC.TARGETS[cfg.ecu][STATES[k].t]
  local m = run.m[k]
  if m == nil then
    return tg .. "  --"
  end
  return string.format("%d  %d  %s", tg, m, math.abs(m - tg) <= cfg.tol and "PASS" or "FAIL")
end

-- Most likely cause for a failed state (contracts/verify.md "Diagnosis").
local function diagnose(k, m)
  local tg = REC.TARGETS[cfg.ecu]
  local cut, idle, full = tg[1], tg[2], tg[3]
  if k == 1 then
    if m > cut + cfg.tol then
      return "Cut too high. Throttle Cut", string.format("Output value should be %d%%.", REC.CUT_VAL[cfg.ecu])
    end
    return "Cut low. Check Max negative", string.format("(%d%%) and Throttle-Cut value.", REC.MAX_NEG)
  elseif k == 2 then
    if near(m, full) then
      return "Cut doesn't override stick.", "Check Throttle Cut switch."
    end
    return "Cut changes with stick.", "Check Throttle Cut settings."
  elseif k == 3 then
    if near(m, cut) then
      return "Switch RUN gave cut.", "Check Throttle Idle switch."
    end
    return string.format("Idle off by %+d us. Check Idle", m - idle),
      string.format("offset (%d%%) and throttle trim.", REC.IDLE_OFS)
  end
  return string.format("Full off by %+d us. Check Max", m - full),
    string.format("positive (%d%%) and trim.", REC.MAX_POS)
end

local function setButtonsVerify()
  if not formOpen or cur ~= SCR.VERIFY then
    return
  end
  local p = run.phase
  form.setButton(1, "Back", ENABLED)
  form.setButton(3, "Retry", p == PH.FAILED and ENABLED or 3)
  local f5 = "Start"
  if p == PH.FAILED or (p == PH.PASSED and run.retried) then
    f5 = "Restart"
  elseif p == PH.PASSED then
    f5 = "Next"
  end
  local show = p == PH.IDLE or p == PH.FAILED or p == PH.PASSED
  form.setButton(5, f5, show and ENABLED or 3)
end

local function showRows()
  if not formOpen or cur ~= SCR.VERIFY or not idx.vRow then
    return
  end
  for k = 1, 4 do
    form.setProperties(idx.vRow[k], { label = run.row[k] })
  end
  form.setProperties(idx.vWhy1, { label = run.why1, visible = run.why1 ~= "" })
  form.setProperties(idx.vWhy2, { label = run.why2, visible = run.why2 ~= "" })
end

local function setPhase(p)
  run.phase = p
  setButtonsVerify()
end

local function startRun()
  run.k, run.retried, run.m, run.why1, run.why2 = 0, false, {}, "", ""
  run.chkIdle, run.chkFull = nil, nil
  for k = 1, 4 do
    run.row[k] = resultRow(k)
  end
  showRows()
  setPhase(PH.CHECK)
end

local function fail(line1, line2)
  run.why1, run.why2 = line1, line2
  showRows()
  setPhase(PH.FAILED)
end

-- A clean run passed: save it (FR-019, data-model "Transitions").
local function savePass()
  local dt = system.getDateTime()
  save("meas", { run.m[1], run.m[2], run.m[3], run.m[4] })
  save("when", dt.year * 10000 + dt.mon * 100 + dt.day)
  save("res", RES.PASSED)
end

-- One verify step, at most every SAMPLE_MS while the Verify screen is open.
-- Returns the "Do" pair to show (a constant from DO).
local function stepVerify(now, sv, kv, ov)
  local p = run.phase
  if p == PH.IDLE then
    return DO.start
  elseif p == PH.FAILED then
    return DO.failed
  elseif p == PH.PASSED then
    return run.retried and DO.retried or DO.passed
  end
  if sv == nil or kv == nil or ov == nil then
    return DO.inputs
  end
  local us = US_CENTER + US_PER_UNIT * ov
  local tg = REC.TARGETS[cfg.ecu]

  if p == PH.CHECK then                 -- output check (R7, FR-017)
    if not switchIs(false, sv) then
      return DO.toRun
    end
    if stickAt(true, kv) then
      run.chkIdle = us
    elseif stickAt(false, kv) and run.chkIdle then
      run.chkFull = us
    end
    if run.chkIdle and run.chkFull then
      local span = math.abs(run.chkFull - run.chkIdle)
      if span < (tg[3] - tg[2]) // 2 then
        if near(run.chkIdle, tg[1]) then
          fail("Switch RUN gave cut.", "Reverse the switch assignment.")
        else
          fail("Output doesn't move with stick.", "Choose the throttle output.")
        end
      elseif run.chkFull < run.chkIdle then
        fail("Throttle reversed.", "Check Servo setup > Reverse.")
      else
        run.k = 1
        setPhase(PH.WAIT)
      end
    end
    if run.phase == PH.FAILED then
      return DO.failed
    elseif run.phase ~= PH.CHECK then
      return DO.steady
    end
    return run.chkIdle and DO.checkFull or DO.toIdle
  end

  local st = STATES[run.k]
  local inPos = switchIs(st.cut, sv) and stickAt(st.idle, kv)
  if p == PH.WAIT then
    if inPos then
      run.t0, run.refOut, run.refStk = now, us, kv
      setPhase(PH.SETTLE)
      return DO.steady
    end
    if not switchIs(st.cut, sv) then
      return st.cut and DO.toCut or DO.toRun
    end
    return st.idle and DO.toIdle or DO.toFull
  end
  if not inPos then                    -- position lost: wait again (FR-015)
    setPhase(PH.WAIT)
    return DO.steady
  end
  if p == PH.SETTLE then
    if math.abs(kv - run.refStk) > V.STICK_JITTER or math.abs(us - run.refOut) > V.OUT_JITTER_US then
      run.t0, run.refOut, run.refStk = now, us, kv
    elseif now - run.t0 >= V.STEADY_MS then
      run.n, run.sum = 0, 0
      setPhase(PH.SAMPLE)
    end
    return DO.steady
  end
  -- SAMPLE: average SAMPLE_N readings, SAMPLE_MS apart (R8)
  run.n, run.sum = run.n + 1, run.sum + us
  if run.n < V.SAMPLE_N then
    return DO.measuring
  end
  local m = math.floor(run.sum / run.n + 0.5)
  local target = tg[st.t]
  run.m[run.k] = m
  run.row[run.k] = resultRow(run.k)
  if math.abs(m - target) <= cfg.tol then  -- FR-014
    showRows()
    if run.k < 4 then
      run.k = run.k + 1
      setPhase(PH.WAIT)
    else
      if not run.retried then
        savePass()
      end
      setPhase(PH.PASSED)
    end
  else
    fail(diagnose(run.k, m))
  end
  return DO.steady
end

-- A labelled row ("Test:", "Set:", "Now:", "Do:") whose value changes.
local function addInfoRow(name, font)
  form.addRow(2)
  form.addLabel({ label = name, width = 50, font = FONT_MINI })
  return form.addLabel({ label = "", font = font or FONT_NORMAL })
end

local function buildVerify()
  form.setTitle("Verify")
  form.addRow(1)
  form.addLabel({ label = "ENGINE MUST NOT BE ABLE TO START", font = FONT_BOLD })
  hint("(fuel off or ECU unplugged)")
  hint("Center throttle trim. Checks")
  hint("this flight mode only.")
  idx.vTest = addInfoRow("Test:", FONT_BOLD)
  idx.vSet1 = addInfoRow("Set:")
  idx.vSet2 = addInfoRow("")
  idx.vNow = addInfoRow("Now:")
  idx.vDo1 = addInfoRow("Do:", FONT_BOLD)
  idx.vDo2 = addInfoRow("")
  hint("State           target  measured")
  idx.vRow = {}
  for k = 1, 4 do
    if run.row[k] == nil then
      run.row[k] = resultRow(k)
    end
    form.addRow(2)
    form.addLabel({ label = STATES[k].name, width = 130 })
    idx.vRow[k] = form.addLabel({ label = run.row[k], alignRight = true })
  end
  idx.vWhy1 = hint(run.why1, run.why1 ~= "")
  idx.vWhy2 = hint(run.why2, run.why2 ~= "")
  run.shownInfo, run.shownDo, run.shownSw, run.shownStk = nil, nil, nil, nil
  setButtonsVerify()
end

local function verifyKey(keyCode)
  local p = run.phase
  if keyCode == KEY_1 then
    setPhase(PH.IDLE)                  -- Back abandons a run
    goTo(SCR.HOME)
  elseif keyCode == KEY_3 and p == PH.FAILED then
    run.retried = true                 -- diagnosis only (clarification Q1)
    run.why1, run.why2 = "", ""
    showRows()
    if run.k == 0 then
      run.chkIdle, run.chkFull = nil, nil
      setPhase(PH.CHECK)
    else
      setPhase(PH.WAIT)
    end
  elseif keyCode == KEY_5 then
    if p == PH.IDLE or p == PH.FAILED or (p == PH.PASSED and run.retried) then
      startRun()
    elseif p == PH.PASSED then
      setPhase(PH.IDLE)
      goTo(SCR.FAILSAFE)
    end
  end
end

-- Run one verify step and refresh the Test / Set / Now / Do rows, each only
-- when what it shows has changed.
local function updateVerify(now)
  if now - (run.lastWork or 0) < V.SAMPLE_MS then
    return
  end
  run.lastWork = now
  local sv, kv, ov = readSwitch(), readStick(), readOut()
  local act = stepVerify(now, sv, kv, ov)

  local info = STATES[run.k] or CHECK_INFO
  if run.phase == PH.IDLE then
    info = READY_INFO
  end
  if info ~= run.shownInfo then
    run.shownInfo = info
    form.setProperties(idx.vTest, { label = info.test })
    form.setProperties(idx.vSet1, { label = info.set1 })
    form.setProperties(idx.vSet2, { label = info.set2 })
  end
  if act ~= run.shownDo then
    run.shownDo = act
    form.setProperties(idx.vDo1, { label = act[1] })
    form.setProperties(idx.vDo2, { label = act[2] })
  end
  local sw, stk = switchText(sv), stickText(kv)
  if sw ~= run.shownSw or stk ~= run.shownStk then
    run.shownSw, run.shownStk = sw, stk
    form.setProperties(idx.vNow, { label = "switch " .. sw .. ", stick " .. stk })
  end
end

------------------------------------------------------------------------------
-- Failsafe confirmation and Summary (contracts/screens.md sections 5, 6)
------------------------------------------------------------------------------

local function buildFailsafe()
  form.setTitle("Failsafe test")
  hint("With the ECU powered and fuel")
  hint("OFF, switch the transmitter off.")
  form.addRow(1)
  form.addLabel({ label = "Does the ECU show signal loss?", font = FONT_BOLD })
  form.setButton(1, "Not yet", ENABLED)
  form.setButton(5, "Yes", ENABLED)
end

local function failsafeKey(keyCode)
  if keyCode == KEY_5 then
    save("res", RES.COMPLETE)
    goTo(SCR.SUMMARY)
  elseif keyCode == KEY_1 then
    goTo(SCR.SUMMARY)                  -- result stays "failsafe not confirmed"
  end
end

local function buildSummary()
  form.setTitle("Summary")
  addStatus()
  local info = cfg.sw and system.getSwitchInfo(cfg.sw)
  local label = info and info.label or "?"
  hint(string.format("Safety switch: %s, CUT at %s", label, cfg.offSg > 0 and "+100%" or "-100%"))
  if cfg.ecu > 0 then
    hint(string.format("ECU: %s (cut %d%%)", ECU_NAMES[cfg.ecu + 1], REC.CUT_VAL[cfg.ecu]))
    hint(targetsText(cfg.ecu))
  end
  local m = cfg.meas
  if type(m) == "table" and #m == 4 then
    hint(string.format("Measured: %d/%d/%d/%d", m[1], m[2], m[3], m[4]))
  end
  if cfg.when > 0 then
    hint("Verified: " .. fmtDate(cfg.when))
  end
  form.addRow(1)
  form.addLabel({ label = "Next:", font = FONT_BOLD })
  hint("Remove this app from the")
  hint("model, then re-learn your ECU")
  hint("(Teach RC). Always re-learn")
  hint("after changing these values.")
  form.setButton(1, "Back", ENABLED)
end

local BUILD = {
  [SCR.HOME] = buildHome,
  [SCR.INPUTS] = buildInputs,
  [SCR.GUIDE] = buildGuide,
  [SCR.VERIFY] = buildVerify,
  [SCR.FAILSAFE] = buildFailsafe,
  [SCR.SUMMARY] = buildSummary,
  [SCR.VOICE] = buildVoice,
}

-- Where to land when the form opens (FR-009, research R4): the saved
-- screen, unless it isn't allowed yet.
local function resolveScreen(s)
  if (s == SCR.GUIDE or s == SCR.VERIFY) and not setupComplete() then
    return SCR.HOME
  elseif s == SCR.FAILSAFE and cfg.res ~= RES.PASSED then
    return cfg.res > RES.NONE and SCR.SUMMARY or SCR.HOME
  elseif s == SCR.SUMMARY and cfg.res == RES.NONE then
    return SCR.HOME
  end
  return s
end

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

local function initForm()
  formOpen = true
  idx = {}
  cur = resolveScreen(cur)
  local ok, err = pcall(BUILD[cur])
  if not ok then
    idx = {}
    showError("build " .. cur, err)
  end
end

-- Screens whose own F-keys replace the default handling.
local SCREEN_KEYS = { [SCR.GUIDE] = guideKey, [SCR.VERIFY] = verifyKey, [SCR.FAILSAFE] = failsafeKey }

local function onKey(keyCode)
  local handler = SCREEN_KEYS[cur]
  if handler then
    if keyCode == KEY_5 then
      form.preventDefault()           -- F5 would otherwise close the form
    end
    if keyCode ~= KEY_RELEASED then
      handler(keyCode)
    end
  elseif keyCode == KEY_1 and cur ~= SCR.HOME then
    goTo(SCR.HOME)
  elseif cur == SCR.INPUTS then
    if keyCode == KEY_3 then
      learn()
    end
  elseif cur == SCR.VOICE then
    if keyCode == KEY_2 and canCopy() then
      if form.question("Copy voice files?", "TurbOff.wav, TurbOn.wav to " .. VOICE.dest,
          "Files already there are kept.") == 1 then
        startCopy()
      end
    elseif keyCode == KEY_3 and canOpenMenus() then
      system.openExternal(MENU.sound)
    end
  end
end

-- The form is gone: drop its indices so nothing calls form.* on them (R9).
local function closeForm()
  formOpen = false
  idx = {}
  if run.phase ~= PH.PASSED and run.phase ~= PH.FAILED then
    run.phase = PH.IDLE                -- a half-finished run is never resumed
  end
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
  local lang = system.getLocale()
  if type(lang) == "string" and lang ~= "" then
    VOICE.dest = "/Audio/" .. lang
  end
  loadSettings()
  refreshOutCode()
  cur = cfg.scr
  system.registerForm(1, MENU_APPS, APP_NAME, initForm, onKey, nil, closeForm)
end

local function loop()
  local j = job
  if j then                  -- the copy continues even with the form closed (R15)
    local ok, err = pcall(stepCopy, j)
    if not ok then
      print("TrbSt copy: " .. tostring(err))
      if job then
        finishFile(job, "error")
      end
    end
  end
  if not formOpen then
    return
  end
  if cur == SCR.VERIFY and idx.vTest then
    local ok, err = pcall(updateVerify, system.getTimeCounter())
    if not ok then
      print("TrbSt verify: " .. tostring(err))
      idx.vTest = nil         -- stop retrying every loop
    end
  elseif cur == SCR.INPUTS and idx.us then
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
  if job then                -- don't leave a half-written file in /Audio
    pcall(finishFile, job, "stopped")
    job = nil
  end
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
