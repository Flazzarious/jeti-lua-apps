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

local function canCopy()
  if job or not vsrcOk then
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
  hint("Copy puts them in the voice")
  hint("folder above.")
  hint("Sounds on event: add the")
  hint("safety switch at CUT with")
  hint("TurbOff.wav, and at RUN with")
  hint("TurbOn.wav. Keep any callouts")
  hint("you already have, or use your")
  hint("own files.")
  hint("Voice: Piper, Amy (CC BY-SA 4.0).")
  form.setButton(1, "Back", ENABLED)
  form.setButton(2, "Copy", canCopy() and ENABLED or DISABLED)
  if canOpenMenus() then
    form.setButton(3, "Open", ENABLED)
  end
end

local function buildHome()
  form.setTitle(APP_NAME)
  form.addRow(1)
  form.addLink(function() goTo(SCR.INPUTS) end, { label = "Setup inputs" })
  form.addRow(1)
  form.addLink(function() goTo(SCR.VOICE) end, { label = "Voice callouts (optional)" })
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
  [SCR.VOICE] = buildVoice,
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

local function initForm()
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
