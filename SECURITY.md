# Security policy

These apps run on JETI radio transmitters, which are flight equipment. They
have no network access and handle no personal data, so "security" here mostly
means **safety and integrity**: nothing an app does may affect flight, and
what you install must be exactly what was released.

## Supported versions

Only the **latest release of each app** gets fixes. Install the newest version
through JETI Studio, or from the app's newest
[release](https://github.com/Flazzarious/jeti-lua-apps/releases).

| App | Script | Supported |
| --- | --- | --- |
| Speed Gauge | `AG-SpdGa.lua` | latest release |
| Flameout Alarm | `AG-FlmOt.lua` | latest release |
| Throttle Setup Wizard | `AG-TrbSt.lua` | latest release |
| Battery Capacity | `AG-BatCp.lua` | latest release |

## What to report privately

Report these privately (see below), not in a public issue:

- **Anything that could affect flight:** an app that changes a control,
  output, channel, trim, failsafe or other model setting, or that could make
  the transmitter misbehave in flight. Apps must never do this (see the
  [constitution](.specify/memory/constitution.md), principle I).
- **Integrity of installs:** `Apps.json` pointing at files other than the
  tagged release, files whose hashes don't match, or any way to get a user to
  install modified files through this repository's app source.
- **Malicious or hidden code** in an app, a shared `lib` module or a tool in
  `tools/`.
- **Leaked secrets** committed to the repository.

Ordinary bugs, including an alarm that doesn't sound or a wrong reading, go
in a normal [bug report](https://github.com/Flazzarious/jeti-lua-apps/issues/new/choose).
If an app misbehaves in a way that could matter in flight, stop using it on
that model and report it straight away.

## How to report

Use GitHub's private vulnerability reporting: open the repository's
**Security** tab and choose **Report a vulnerability**
([direct link](https://github.com/Flazzarious/jeti-lua-apps/security/advisories/new)).
Only the maintainer sees the report.

Please include the app and version, your transmitter and firmware, what
happens and how to reproduce it.

## What happens next

This is a one-person hobby project, so there are no guaranteed response
times, but safety reports come first:

- you'll get an acknowledgment, normally within a week;
- a confirmed problem is fixed in a new release and, if needed, the affected
  version is withdrawn from the JETI Studio app list;
- the fix is credited to you in the release notes unless you'd rather not
  be named.

The apps are provided under the MIT license, without warranty (see
[LICENSE](LICENSE)). They are advisory only and don't replace your own
checks, your ECU's failsafe or your transmitter's own alarms.
