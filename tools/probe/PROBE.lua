-- PROBE.lua — measures the transmitter's Lua drawing areas. Dev tool, not an app.
-- Copyright (c) 2026 Aaron George
-- SPDX-License-Identifier: MIT
--
-- Copy to the emulator's (or a test transmitter's) Apps folder, add
-- "Screen Probe" in Applications > User Applications, then put each of its
-- windows on the desktop via Timers/Sensors > Displayed telemetry:
--   "Probe small" (size 1), "Probe large" (size 2).
-- Open the app's form ("Screen Probe" in the Applications menu) to see the
-- full-screen form canvas size.
-- Every size is shown on screen and printed once to the Lua debug console.

local reported = {}

local function report(tag, w, h)
  if reported[tag] ~= w * 10000 + h then
    reported[tag] = w * 10000 + h
    print("PROBE " .. tag .. ": " .. w .. " x " .. h)
  end
end

local function drawInfo(tag, w, h)
  report(tag, w, h)
  lcd.drawRectangle(0, 0, w, h)
  lcd.drawLine(0, 0, w - 1, h - 1)
  lcd.drawText(4, 2, tag .. " " .. w .. "x" .. h, FONT_BOLD)
  lcd.drawText(4, 2 + lcd.getTextHeight(FONT_BOLD), "fonts N/B/M/Mx: "
    .. lcd.getTextHeight(FONT_NORMAL) .. "/" .. lcd.getTextHeight(FONT_BIG)
    .. "/" .. lcd.getTextHeight(FONT_MINI) .. "/" .. lcd.getTextHeight(FONT_MAXI), FONT_MINI)
end

local function printSmall(w, h) drawInfo("small", w, h) end
local function printLarge(w, h) drawInfo("large", w, h) end
local function printForm(w, h) drawInfo("form", w, h) end

local function init()
  print("PROBE device: " .. tostring(system.getDeviceType())
    .. ", firmware " .. tostring(system.getVersion()))
  system.registerTelemetry(1, "Probe small", 1, printSmall)
  system.registerTelemetry(2, "Probe large", 2, printLarge)
  system.registerForm(1, MENU_APPS, "Screen Probe", nil, nil, printForm)
end

return { init = init, loop = nil, author = "Aaron George", version = "1.0", name = "Screen Probe" }
