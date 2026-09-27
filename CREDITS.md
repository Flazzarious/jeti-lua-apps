# Credits and third-party notices

Apps in this repository build on work that others shared freely with the Jeti
community. This file credits that work and carries the license notices it
requires.

## Speed Gauge (`AG-SpdGa`) — based on DFM Speed Announcer

Speed Gauge is a rewrite of **DFM Speed Announcer** (`DFM-SpdA.lua`,
version 2.1) by **DFM, Dave McQueeney**
([github.com/davidmcq137/JetiLuaDFM](https://github.com/davidmcq137/JetiLuaDFM),
[jetiluadfm.app](https://www.jetiluadfm.app)). Much of Speed Gauge's behavior
comes directly from that app:
- the variable announcement interval that speeds up when speed changes;
- fast callouts below landing speed;
- the stall, overspeed and "airspeed alive" warnings and their sounds;
- the continuous-callouts switch;
- sensor calibration and unit handling.

Speed Gauge exists because that work made it possible. The original is kept
unmodified in
[`docs/examples/dfm-speed-announce/`](docs/examples/dfm-speed-announce/).

DFM Speed Announcer was itself inspired by Tero's Altitude Announcer
from [RC-Thoughts.com](https://www.rc-thoughts.com), whose style it followed.

DFM Speed Announcer is released under the MIT license. Its source header reads
"Released under MIT-license by DFM 2018, 2019". The notice below applies to
the portions of Speed Gauge derived from it, including the reused WAV files:

```text
MIT License

Copyright (c) 2018, 2019 DFM (Dave McQueeney)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## JETI model official demos

[`docs/examples/jeti-demos/`](docs/examples/jeti-demos/) holds unmodified demos
from [JETImodel/Lua-Apps](https://github.com/JETImodel/Lua-Apps), Copyright (c)
2016 JETI model s.r.o. They are redistributed under their BSD-style license,
whose full text is kept at the top of each file. The API facts in
`types/jeti.lua` and `docs/jeti-api-notes.md` are summarized from JETI's Lua
API document.

## Emulator Telemetry

Emulator testing relies on LeonAirRC's Emulator Telemetry app
([LeonAirRC/Jeti-Lua-Apps](https://github.com/LeonAirRC/Jeti-Lua-Apps)). It is
installed separately and not included here.
