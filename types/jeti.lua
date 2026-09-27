---@meta
-- LuaLS type stubs for the JETI DC/DS Lua API.
--
-- Source: JETI DC/DS Lua Programming API v1.5 (2019-12-17), cross-checked
-- against the official demos in github.com/JETImodel/Lua-Apps.
-- Lines tagged UNVERIFIED are inferred where the PDF is silent; confirm them
-- in the emulator before relying on them.
--
-- This file is never deployed. It exists so LuaLS can autocomplete, type-check
-- and flag calls to functions that don't exist. If a function is missing here,
-- look it up in the API PDF and add it with a source note before using it.
--
-- Constitution reminders are marked FORBIDDEN / CAUTION on the relevant stubs.

------------------------------------------------------------------------------
-- Opaque and structured types
------------------------------------------------------------------------------

---A switch or control assignment chosen by the user (form.addInputbox) or
---built with system.createSwitch. Persist it with system.pSave.
---@class SwitchItem: userdata

---@class GpsPoint: userdata

---@class ImageData: userdata

---@class Image
---@field width integer
---@field height integer
---@field data ImageData

---@class JetiFile: userdata

---@class SensorEntry
---@field id integer Sensor unique identifier.
---@field param integer Parameter identifier; 0 is the sensor's name row.
---@field decimals integer Digits after the decimal point.
---@field type integer Data type; 5 = date/time, 9 = GPS.
---@field label string Telemetry label, or sensor name when param == 0.
---@field unit string Default (unconverted) unit.
---@field valid boolean True if refreshed recently.
---@field sensorName string Name of the owning EX sensor.
---@field value number
---@field min number
---@field max number
---@field valSec integer
---@field valMin integer
---@field valHour integer
---@field valYear integer
---@field valMonth integer
---@field valDay integer
---@field valGPS integer Packed GPS value; decode with bit ops or use gps.*.

---Lighter entry returned by system.getSensorValueByID (no label/unit/name).
---@class SensorValue
---@field type integer
---@field valid boolean
---@field value number
---@field min number
---@field max number
---@field valSec integer
---@field valMin integer
---@field valHour integer
---@field valYear integer
---@field valMonth integer
---@field valDay integer
---@field valGPS integer

---@class DateTime
---@field year integer
---@field mon integer 1-12
---@field day integer 1-31
---@field hour integer
---@field min integer
---@field sec integer
---@field dst boolean Daylight saving time (V4.22+).

---@class TxTelemetry
---@field txVoltage number [V]
---@field txBattPercent number [%]
---@field txCurrent number [mA]
---@field txCapacity number [mAh]
---@field rx1Percent number Signal quality, primary receiver [%]
---@field rx1Voltage number [V]
---@field rx2Percent number
---@field rx2Voltage number
---@field rxBVoltage number Backup (900 MHz) receiver voltage [V]
---@field rxBPercent number
---@field photoValue integer Light sensor, 0-4096
---@field RSSI integer[] Rx1 A1, Rx1 A2, Rx2 A1, Rx2 A2, RxB A1, RxB A2

---@class SwitchInfo
---@field label string
---@field value number -1..1
---@field proportional boolean
---@field assigned boolean
---@field mode string Letters from S, P, I, C (V5.01+).

---@class Imu
---@field r number Roll angle.
---@field p number Pitch angle.
---@field y number Yaw angle.
---@field ax number Acceleration without gravity, 1G ~ 1.0.
---@field ay number
---@field az number

---@class RawImu
---@field ax integer
---@field ay integer
---@field az integer
---@field gx integer
---@field gy integer
---@field gz integer

---@class Renderer
local Renderer = {}
---@param x number
---@param y number
function Renderer:addPoint(x, y) end
function Renderer:reset() end
---@param alpha? number 0.0-1.0, default 1.0
function Renderer:renderPolygon(alpha) end
---@param width number
---@param alpha? number 0.0-1.0, default 1.0
function Renderer:renderPolyline(width, alpha) end
---@param x integer
---@param y integer
---@param width integer
---@param height integer
function Renderer:setClipping(x, y, width, height) end

---Common optional parameters accepted by form components.
---@class FormParams
---@field label? string
---@field font? integer FONT_* constant.
---@field alignRight? boolean
---@field enabled? boolean
---@field visible? boolean
---@field width? integer

---The table an app file must return.
---@class JetiApp
---@field init? fun(code?: integer) 0 fresh load, 1 model load/change, 2 after USB disconnect.
---@field loop? fun()
---@field destroy? fun() V5.00+
---@field author? string
---@field version? string
---@field name? string

------------------------------------------------------------------------------
-- Global constants
------------------------------------------------------------------------------

DISABLED = 0
ENABLED = 1
HIGHLIGHTED = 2

---@type integer
FONT_NORMAL = nil
---@type integer
FONT_BOLD = nil
---@type integer
FONT_MINI = nil
---@type integer
FONT_BIG = nil
---@type integer
FONT_MAXI = nil
---@type integer Monochrome displays only (DC/DS-16).
FONT_REVERSED = nil
---@type integer Monochrome displays only.
FONT_GRAYED = nil
---@type integer Monochrome displays only.
FONT_XOR = nil
---@type integer Monochrome displays only.
FONT_OR = nil
---@type integer Monochrome displays only.
FONT_AND = nil

---@type integer
MENU_NONE = nil
---@type integer
MENU_MAIN = nil
---@type integer
MENU_FINE = nil
---@type integer
MENU_ADVANCED = nil
---@type integer
MENU_APPS = nil
---@type integer
MENU_SYSTEM = nil
---@type integer
MENU_GAMES = nil

---@type integer Persistent data scope: all models. How to pass it is undocumented in v1.5.
SYSTEM = nil
---@type integer Persistent data scope: this model.
MODEL = nil

---@type integer
AUDIO_BACKGROUND = nil
---@type integer
AUDIO_IMMEDIATE = nil
---@type integer
AUDIO_QUEUE = nil

---@type integer
SOUND_START = nil
---@type integer
SOUND_BOUND = nil
---@type integer
SOUND_LOWTXVOLT = nil
---@type integer
SOUND_LOWSIGNAL = nil
---@type integer
SOUND_SIGNALLOSS = nil
---@type integer
SOUND_RANGETEST = nil
---@type integer
SOUND_AUTOTRIM = nil
---@type integer
SOUND_INACT = nil
---@type integer
SOUND_LOWQ = nil
---@type integer
SOUND_RXRESET = nil

---@type integer
KEY_1 = nil
---@type integer
KEY_2 = nil
---@type integer
KEY_3 = nil
---@type integer
KEY_4 = nil
---@type integer
KEY_5 = nil
---@type integer
KEY_MENU = nil
---@type integer
KEY_ESC = nil
---@type integer
KEY_ENTER = nil
---@type integer
KEY_UP = nil
---@type integer
KEY_DOWN = nil
---@type integer
KEY_RELEASED = nil
---@type integer Named in form.preventDefault docs; not in the key table. UNVERIFIED
KEY_POWER = nil

------------------------------------------------------------------------------
-- system
------------------------------------------------------------------------------

---@class systemlib
system = {}

---Lua CPU use for the current call, 0-100. At 100 the script is killed.
---@return integer
function system.getCPU() end

---Seconds since 2000-01-01 00:00:00.
---@return integer
function system.getTime() end

---Milliseconds timestamp. Use for intervals and rate limiting.
---@return integer
function system.getTimeCounter() end

---@return DateTime
function system.getDateTime() end

---Firmware version string, e.g. "5.06".
---@return string
function system.getVersion() end

---e.g. "JETI DC-24".
---@return string
function system.getDeviceType() end

---e.g. "en".
---@return string
function system.getLocale() end

---@return TxTelemetry
function system.getTxTelemetry() end

---@return string
function system.getUserName() end

---@return string
function system.getSerialCode() end

---All sensors and parameters. Heavy: call from setup forms, not loop().
---@return SensorEntry[]
function system.getSensors() end

---@param sensorId integer
---@param param integer 0 = sensor name row.
---@return SensorEntry|nil
function system.getSensorByID(sensorId, param) end

---Lighter than getSensorByID; prefer it in loop().
---@param sensorId integer
---@param param integer
---@return SensorValue|nil
function system.getSensorValueByID(sensorId, param) end

---Raw control values, -1..1, all sampled in the same frame. Up to 8 names:
---"P1".."P10", "SA".."SP", "T1".."T16", "CH1".."CH8", "O1".."O24".
---@param ... string
---@return number|nil ...
function system.getInputs(...) end

---Values of SwitchItems (from form.addInputbox / system.createSwitch), up to 8.
---@param ... SwitchItem
---@return number|nil ...
function system.getInputsVal(...) end

---DS transmitters only.
---@param smoothed? integer 0 (default) = unfiltered.
---@return Imu
function system.getIMU(smoothed) end

---DS transmitters only.
---@return RawImu
function system.getRawIMU() end

---FORBIDDEN in this repo (Constitution I): can switch wireless/trainer mode.
---@deprecated
---@param name string
---@param value any
function system.setProperty(name, value) end

---@param name string
---@return any
function system.getProperty(name) end

---V4.22+
---@param switch SwitchItem
---@return SwitchInfo|nil
function system.getSwitchInfo(switch) end

---Status-bar message.
---@param message string
---@param timeoutSeconds? integer Default 3; 0 clears immediately.
function system.messageBox(message, timeoutSeconds) end

---Up to 2 per app. Call from init().
---@param windowNo integer 1 or 2
---@param label string Max 31 bytes.
---@param size integer 0 auto, 1 small, 2 large, 3 full screen + status bar, other full screen.
---@param printFunction fun(width: integer, height: integer)
---@return integer|nil
function system.registerTelemetry(windowNo, label, size, printFunction) end

---@param windowNo integer
function system.unregisterTelemetry(windowNo) end

---Up to 2 per app. Call from init().
---@param formNo integer 1 or 2
---@param parentMenuID integer MENU_* constant, or 0 to show immediately.
---@param label string Max 31 bytes.
---@param initFunction? fun(subformId: integer)
---@param keyPressFunction? fun(keyCode: integer)
---@param printFunction? fun(width: integer, height: integer)
---@param closeFunction? fun() V5.00+
---@return integer|nil
function system.registerForm(formNo, parentMenuID, label, initFunction, keyPressFunction, printFunction, closeFunction) end

---@param formNo integer
function system.unregisterForm(formNo) end

---FORBIDDEN in this repo (Constitution I): the control can be assigned to flight functions.
---@deprecated
---@param controlNo integer 1-10
---@param label string Max 31 bytes.
---@param shortLabel string Max 3 bytes.
---@return integer|nil
function system.registerControl(controlNo, label, shortLabel) end

---FORBIDDEN in this repo (Constitution I).
---@deprecated
---@param controlNo integer
---@param value number -1..1
---@param delayms integer
---@param smoothType? integer 0 linear, 1 low-pass.
---@return true|nil
function system.setControl(controlNo, value, delayms, smoothType) end

---FORBIDDEN in this repo (Constitution I).
---@deprecated
---@param controlNo integer
function system.unregisterControl(controlNo) end

---Adds a virtual value to the telemetry log (~200 ms period). Max 24 on DC/DS-24.
---Callback returns an integer value and, optionally, its number of decimals.
---@param label string Max 14 bytes.
---@param unit string Max 4 bytes.
---@param callback fun(index: integer): integer, integer?
---@return integer|nil
function system.registerLogVariable(label, unit, callback) end

---@param logVariableId integer
function system.unregisterLogVariable(logVariableId) end

---Loads a per-model persistent value (available before init() runs).
---@generic T
---@param param string Key, < 64 bytes.
---@param defaultValue? T
---@return any|T
function system.pLoad(param, defaultValue) end

---Saves a per-model value on model switch/power-off. Stores integer, string
---(< 64 bytes), SwitchItem, array of <= 32 integers/strings, or nil to delete.
---NOT floats: scale them to integers.
---@param param string Key, < 64 bytes.
---@param value integer|string|SwitchItem|(integer|string)[]|nil
---@return true|nil
function system.pSave(param, value) end

---@param rightStick boolean false = left, true = right.
---@param profile integer 1 long, 2 short, 3 two short, 4 three short, other = stop.
function system.vibration(rightStick, profile) end

---Relative paths resolve under /Audio and /Audio/<lang>. Foreground types are WAV only.
---@param fileName string
---@param playbackType? integer AUDIO_* constant.
function system.playFile(fileName, playbackType) end

---Text-to-speech number. unit/label must exist in Voice/XX/numbers.jsn.
---@param value number
---@param decimals integer 0-2
---@param unit? string
---@param label? string
---@return true|nil
function system.playNumber(value, decimals, unit, label) end

---@param repeatCount integer 0-10 additional beeps.
---@param frequency integer 200-10000 Hz
---@param length integer 20-10000 ms
function system.playBeep(repeatCount, frequency, length) end

---@param soundIndex integer SOUND_* constant.
function system.playSystemSound(soundIndex) end

---@param playbackType? integer AUDIO_BACKGROUND or AUDIO_IMMEDIATE; omit to stop all.
function system.stopPlayback(playbackType) end

---V4.22+
---@return boolean
function system.isPlayback() end

---V5.00+. Drives the acoustic vario.
---@param value number -1..1, positive = climb.
---@param shortTone boolean
---@param disableOutput boolean
function system.setVario(value, shortTone, disableOutput) end

---V5.01+. Opens a .txt/.html/.png/.jpg in the system viewer (async).
---@param path string Absolute path.
function system.openExternal(path) end

---V5.01+
---@param name string "P1".."P10", "SA".."SP", "L1".."L24", "CH1".."CH8"
---@param modifiers string Letters from S, P, I, C.
---@param activeOn? number -1..1
---@return SwitchItem
function system.createSwitch(name, modifiers, activeOn) end

------------------------------------------------------------------------------
-- lcd (only inside registered print functions)
------------------------------------------------------------------------------

---@class lcdlib
lcd = {}

---@param r integer 0-255
---@param g integer 0-255
---@param b integer 0-255
---@param alpha? integer 0-255, default 255
function lcd.setColor(r, g, b, alpha) end

---@return integer r, integer g, integer b
function lcd.getFgColor() end

---@return integer r, integer g, integer b
function lcd.getBgColor() end

---@param x integer
---@param y integer
function lcd.drawPoint(x, y) end

---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
function lcd.drawLine(x1, y1, x2, y2) end

---@param x integer
---@param y integer
---@param text string
---@param font? integer FONT_* constant.
function lcd.drawText(x, y, text, font) end

---@param x integer
---@param y integer
---@param number number
---@param font? integer
function lcd.drawNumber(x, y, number, font) end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param radius? integer
function lcd.drawRectangle(x, y, width, height, radius) end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
---@param alpha? integer 0-255
function lcd.drawFilledRectangle(x, y, width, height, alpha) end

---@param x integer
---@param y integer
---@param radius integer
function lcd.drawCircle(x, y, radius) end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
function lcd.drawEllipse(x, y, width, height) end

---@param x integer
---@param y integer
---@param image Image|string Loaded image, or a system image name like ":ok".
---@param alpha? integer 0-255
function lcd.drawImage(x, y, image, alpha) end

---PNG up to 320x240, baseline JPG up to 1024x768. Slow: load once, not per frame.
---@param absolutePath string
---@return Image|nil
function lcd.loadImage(absolutePath) end

---V5.00+. Off-screen image, max 480x360.
---@param width integer
---@param height integer
---@return Image|nil
function lcd.createImage(width, height) end

---@param font integer
---@return integer
function lcd.getTextHeight(font) end

---@param font integer
---@param text string
---@param maxCharacters? integer
---@return integer
function lcd.getTextWidth(font, text, maxCharacters) end

---@param x integer
---@param y integer
---@param width integer
---@param height integer
function lcd.setClipping(x, y, width, height) end

function lcd.resetClipping() end

---V4.27+, DC/DS-24 only. Anti-aliased polygon/polyline renderer.
---@param image? ImageData V5.00+: render off-screen into this image.
---@return Renderer
function lcd.renderer(image) end

---Screen width in pixels. Used by the official Virtual Sensor app; not in the v1.5 function table. UNVERIFIED
---@type integer
lcd.width = nil

---Screen height in pixels. UNVERIFIED
---@type integer
lcd.height = nil

------------------------------------------------------------------------------
-- form (only while this app's form is displayed)
------------------------------------------------------------------------------

---@class formlib
form = {}

---@param componentsInRow integer
function form.addRow(componentsInRow) end

---@param width integer
---@param height integer
function form.addSpacer(width, height) end

---@param params FormParams
---@return integer|nil index
function form.addLabel(params) end

---@param clickedCallback? fun()
---@param params? FormParams
---@return integer|nil index
function form.addLink(clickedCallback, params) end

---Integer editor, -32768..32767. For decimals pass scaled values (5.0 -> 50, decimals=1).
---@param value integer
---@param minimum integer
---@param maximum integer
---@param defaultValue integer Applied on long press of the rotary button.
---@param decimals integer 0-6
---@param step integer
---@param changedCallback? fun(value: integer)
---@param params? FormParams
---@return integer|nil index
function form.addIntbox(value, minimum, maximum, defaultValue, decimals, step, changedCallback, params) end

---@param values string[] Contiguous, 1-based.
---@param currentIndex integer
---@param enableForm boolean Show options in a standalone dialog.
---@param changedCallback? fun(index: integer)
---@param params? FormParams
---@return integer|nil index
function form.addSelectbox(values, currentIndex, enableForm, changedCallback, params) end

---Picks a WAV from /Audio or /Audio/<lang>.
---@param currentAudioFile string
---@param changedCallback? fun(fileName: string)
---@param params? FormParams
---@return integer|nil index
function form.addAudioFilebox(currentAudioFile, changedCallback, params) end

---@param currentText string
---@param maxCharacters integer 1-63 (UTF-8 multi-byte chars count double).
---@param changedCallback? fun(text: string)
---@param params? FormParams
---@return integer|nil index
function form.addTextbox(currentText, maxCharacters, changedCallback, params) end

---Lets the user assign a control; read it later with system.getInputsVal.
---@param selectedSwitch SwitchItem|nil
---@param enableProportional boolean
---@param changedCallback? fun(switch: SwitchItem)
---@param params? FormParams
---@return integer|nil index
function form.addInputbox(selectedSwitch, enableProportional, changedCallback, params) end

---@param checked boolean
---@param clickedCallback? fun(checked: boolean)
---@param params? FormParams
---@return integer|nil index
function form.addCheckbox(checked, clickedCallback, params) end

---V4.20+. JPG/PNG path or system image name.
---@param path string
---@param params? FormParams
---@return integer|nil index
function form.addIcon(path, params) end

---@param componentIndex integer
---@return integer|string|SwitchItem|nil
function form.getValue(componentIndex) end

---Errors if the type doesn't match the component.
---@param componentIndex integer
---@param newValue integer|string|SwitchItem|boolean
function form.setValue(componentIndex, newValue) end

---@param componentIndex integer
---@param params FormParams
function form.setProperties(componentIndex, params) end

---@param buttonNo integer 1-5
---@param text string Max 7 chars, or ":icon".
---@param state? integer DISABLED (default), ENABLED, HIGHLIGHTED, 3-255 hidden.
function form.setButton(buttonNo, text, state) end

---@param buttonNo integer
---@return string text, integer state
function form.getButton(buttonNo) end

---@return integer|nil formId 0, 1 or 2; nil if none active.
function form.getActiveForm() end

function form.close() end

---Clears and rebuilds the form after the current Lua call returns.
---@param subformId? integer 1-127, default 1.
function form.reinit(subformId) end

---Suppress default handling of KEY_MENU, KEY_5, KEY_ESC, KEY_POWER.
function form.preventDefault() end

function form.waitForRelease() end

---@param rowNumber integer
function form.setFocusedRow(rowNumber) end

---@return integer
function form.getFocusedRow() end

---@param title string
function form.setTitle(title) end

---V4.20+. BLOCKS until answered or timed out. Never call from loop().
---@param boldText string
---@param textLine1? string
---@param textLine2? string
---@param timeoutms? integer 0 = no timeout.
---@param onlyInfo? boolean true = OK button only.
---@param timeoutBeforeOk? integer ms before Yes/No enable.
---@return integer 1 yes, 0 no/timeout, -1 error.
function form.question(boldText, textLine1, textLine2, timeoutms, onlyInfo, timeoutBeforeOk) end

------------------------------------------------------------------------------
-- io (Jeti's reduced, function-style io; NOT the standard Lua io)
------------------------------------------------------------------------------

---@class iolib
io = {}

---@param path string Absolute path on the SD card.
---@param mode? "r"|"w"|"a"
---@return JetiFile|nil
function io.open(path, mode) end

---@param file JetiFile
function io.close(file) end

---@param file JetiFile
---@param noBytes integer
---@return string data Empty string at end of file.
function io.read(file, noBytes) end

---V4.22+
---@param path string
---@return string|nil
function io.readall(path) end

---V4.26+
---@param file JetiFile
---@param skipEOL? boolean
---@return string|nil
function io.readline(file, skipEOL) end

---@param file JetiFile
---@param ... any
---@return JetiFile|nil
function io.write(file, ...) end

---@param file JetiFile
---@param offset integer
---@param mode? "set"|"cur"|"end" V5.1+
---@return integer result 0 on success.
function io.seek(file, offset, mode) end

---V5.00+
---@param oldName string
---@param newName string
---@return true|nil
function io.rename(oldName, newName) end

---V5.00+
---@param fileName string
---@return true|nil
function io.remove(fileName) end

---V5.00+
---@param name string
---@return true|nil
function io.mkdir(name) end

------------------------------------------------------------------------------
-- dir
------------------------------------------------------------------------------

---Directory iterator: `for name, kind, size in dir("/Apps") do ... end`
---@param path string
---@return fun(): (string|nil), ("file"|"folder"|nil), (integer|nil)
function dir(path) end

------------------------------------------------------------------------------
-- json (Lua CJSON subset)
------------------------------------------------------------------------------

---@class jsonlib
json = {}

---@param value any
---@return string
function json.encode(value) end

---Numeric object keys come back as strings; JSON null becomes lightuserdata.
---@param text string
---@return any
function json.decode(text) end

------------------------------------------------------------------------------
-- gps (V5.00+)
------------------------------------------------------------------------------

---@class gpslib
gps = {}

---@param latitude number|string
---@param longitude number|string
---@param altitude? number|string
---@return GpsPoint
function gps.newPoint(latitude, longitude, altitude) end

---@param sensorId integer
---@param paramLat integer
---@param paramLon integer
---@return GpsPoint|nil
function gps.getPosition(sensorId, paramLat, paramLon) end

---@param point GpsPoint
---@param topLeft GpsPoint
---@param zoom integer 1-21
---@return number x, number y
function gps.getLcdXY(point, topLeft, zoom) end

---@param x number
---@param y number
---@param topLeft GpsPoint
---@param zoom integer
---@return GpsPoint
function gps.getLL(x, y, topLeft, zoom) end

---@param point GpsPoint
---@param offsetX number
---@param offsetY number
---@param zoom integer
---@return GpsPoint
function gps.offset(point, offsetX, offsetY, zoom) end

---@param point GpsPoint
---@return number latitude, number longitude
function gps.getValue(point) end

---@param point GpsPoint
---@return string latitude, string longitude
function gps.getString(point) end

---Distance in meters. Second form: (point, latitude, longitude).
---@param point1 GpsPoint
---@param point2OrLat GpsPoint|number
---@param longitude? number
---@return number
function gps.getDistance(point1, point2OrLat, longitude) end

---Initial bearing, 0-360 degrees. Second form: (start, latitude, longitude).
---@param startPoint GpsPoint
---@param destOrLat GpsPoint|number|string
---@param longitude? number|string
---@return number
function gps.getBearing(startPoint, destOrLat, longitude) end

---Point reached after travelling distance (m) on an initial bearing.
---@param point GpsPoint
---@param distance number Meters.
---@param bearing number 0-360 degrees.
---@param altitude? number
---@return GpsPoint
function gps.getDestination(point, distance, bearing, altitude) end

------------------------------------------------------------------------------
-- gpio (V5.00+, DC/DS-24 and DS-12). CAUTION: outputs need a scoped spec.
------------------------------------------------------------------------------

---@class gpiolib
gpio = {}

---CAUTION (Constitution I) when configuring an output.
---@param pin integer 0-8
---@param mode "in"|"out"|"out-pp"|"out-od"
---@param pullup? "up"|"down"
---@return boolean
function gpio.mode(pin, mode, pullup) end

---CAUTION (Constitution I).
---@param pin integer 0-8
---@param value integer 0 or 1
function gpio.write(pin, value) end

---@param pin integer 0-8
---@return integer 0 or 1
function gpio.read(pin) end

------------------------------------------------------------------------------
-- serial (V5.00+, DC/DS-24 and DS-12, 3.3 V UART). CAUTION: writes need a scoped spec.
------------------------------------------------------------------------------

---@class seriallib
serial = {}

---@param portName string "COM1" on the transmitter.
---@param speed integer Baud rate, max 2.8 Mbit/s.
---@return integer|false portId, string? err
function serial.init(portName, speed) end

---@param portId integer
---@return true|nil
function serial.deinit(portId) end

---Callback argument format is not documented in v1.5. UNVERIFIED
---@param portId integer
---@param callback? fun(...: any)
function serial.onRead(portId, callback) end

---CAUTION (Constitution I).
---@param portId integer
---@param ... integer|string
function serial.write(portId, ...) end

---On the transmitter returns { "COM1" }.
---@return string[]
function serial.getPorts() end

---@param portId integer
---@param baudRate integer
function serial.setBaudRate(portId, baudRate) end
