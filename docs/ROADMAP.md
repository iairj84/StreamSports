# Roadmap

Planned work, newest thinking first. Nothing here is a date or a promise; it is
where the next changes are heading and what already constrains them.

## Release channels: beta first, then promote (shipped)

Two channels share one build. Every cut ships from the `beta` branch as a
prerelease tagged `v<version>-<build>`, plus the rolling digit-free
`beta-latest` mirror (`StreamSports-early.apk`, deliberately not GitHub
latest) that testers on the Early channel are offered. The next step below
is done:

- **beta** — early builds, published exactly as now: a prerelease per version
  and the `beta-latest` mirror.
- **main** — stable builds. A beta that has survived a week of real use is
  promoted into main, and the app's normal "new version available" prompt serves
  it.

Promotion reuses the APK that was already published, so the stable download is
byte-for-byte the tested build and keeps the same SHA-256. Adding a stable
mirror release mirrors how `beta-latest` works; it must stay digit-free for the
same reason, because the updater ranks candidate releases by the build number in
the tag.

### In the app

**Settings → Devices & app → App updates** gains a channel choice:

- **Stable only** (the default): only main promotions are offered. A user who
  never opts in is never prompted for a beta.
- **Include early builds**: the newest beta is offered as well, using the same
  download/install flow.

The updater currently asks GitHub for the newest release and ranks candidates by
the build number parsed out of the tag (`lib/services/app_update_service.dart`).
That is enough to ignore `beta-latest`, but not enough to tell a beta from a
stable build of the same version, so the channel has to come from the release
itself — the prerelease flag, or a `stable-latest` mirror asset — rather than
from the version string. Store the preference with the other update settings and
keep the hourly check reading only the channel the user chose.

### Constraints to keep

- One application ID and one `versionCode` stream. A device on beta must not be
  offered a stable build with a lower build number, so promotion never rewrites
  the build number and never re-publishes older bytes.
- Keep the existing tags and assets intact: the Downloader code `1976156` and
  `.../releases/latest/download/StreamSports-beta.apk` are already published and
  cannot be repointed.
- Do not add side-by-side installs (a second application ID) for this; two
  channels over one app is the whole point.
- The release notes name the channel, so a user can tell from the prompt whether
  a build is early or promoted.

### Open naming question

The early channel is called beta today. If a third, rougher tier is ever added as
alpha, the stable channel stays **main** and the opt-in keeps meaning "offer me the
early builds", not "offer me alpha as well".
