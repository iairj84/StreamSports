# StreamSports agent guide

## Project

StreamSports is a free Android IPTV player (phones, TV boxes, Android TV): live TV with a guide, sports events with channel matching, replays and highlights, movies and series, multiview. Bring your own M3U, Xtream or Stalker playlist; the app ships no channels or subscriptions.

Stack: Flutter/Dart, provider state, sqflite catalog/EPG, a video_player_android fork vendored in third_party/. One ARM/arm64 APK, released through GitHub.

Env: Flutter 3.47.7, JDK 21, Android SDK. Copy `.env.example` to `.env`, `chmod 600 .env`; never pass the whole `.env` to `--dart-define-from-file` (secrets would embed in the app).

```sh
flutter pub get        # keep pubspec.lock; verify with --enforce-lockfile
flutter run
flutter analyze
flutter test --concurrency=1
python3 tools/audit_repository.py
python3 -m unittest discover -s tools/tests
flutter build apk --release --target-platform android-arm,android-arm64  # then tools/audit_apk.py on the APK
python3 tools/cut_release.py --notes-file release-notes.txt  # bump, changelog, build, commit, tag, push, publish
```

## Documentation rules

- README.md covers user-facing features and setup; docs/*.md cover install/development/release detail. Update whichever changed.
- CHANGELOG.md gets a dated line for every change, newest first; create it if missing.
- docs/NOTES.md records design decisions, trade-offs and dead ends (why, not what).
- Commit messages explain why: imperative one-line subject, footer `Generated with Codebuff` + `Co-Authored-By: Codebuff <noreply@codebuff.com>`.

## Skill workflow

- New app or feature: brainstorming, then writing-plans, then executing-plans.
- Bug or failing test: systematic-debugging first.
- UI work: frontend-design for direction, checked with webapp-testing.
- Before saying done: verification-before-completion, then requesting-code-review.
- Before putting a web tool online: security-review.
- Commits: git-commit. Docs work: documentation-writer.

## Verification workflow

- During development run `flutter analyze` and the focused tests for the
  change, plus `tools/audit_repository.py` and the tools unit tests when
  touching `tools/`. `python3 tools/preflight.py <test files>` runs all four
  at once and prints each check's time; use it for the gate before a release.
- The full suite is verified by CI's 4-shard matrix (separate machines,
  about 5 minutes). Do not run the 4 shards in parallel in one checkout:
  measured about 37 minutes wall time with 8 timing/perf flakes on code
  that passes the serial run clean, versus about 22 minutes for one serial
  `flutter test --concurrency=1` run. Run the full suite locally only when
  CI cannot cover the change.
- Poll background jobs about every 60 seconds; longer sleeps just add idle
  time after the job already finished.
- Release in as few passes as possible: build the APK, review the
  `tools/audit_apk.py` findings, then run `cut_release.py` with
  `--skip-build --accept-audit-findings` once the only findings are the
  known checkout-path matches. If a run stops after bumping, revert with
  `git checkout -- pubspec.yaml CHANGELOG.md` before retrying so the
  version does not bump twice.

## Release definitions (binding)

These are the meanings used in this repository; do not reinterpret them as a
local-only Git action.

- **"Commit" / "commit to" / "cut and release"** = full delivery, not just
  `git commit`: commit the change, bump the patch version and build number, add
  the CHANGELOG entry, build the release APK, run `tools/audit_apk.py`, commit
  the release, tag it, push `beta`, publish the versioned prerelease and refresh
  the `beta-latest` mirror. Finish only when the APK is published.
- **"Push beta to main"** = fast-forward `main` to `beta`; it does not publish
  the stable channel.
- **"Promote" / "commit to stable" / "release to stable"** = run
  `tools/promote_stable.py --tag <tag>` to republish the tested APK into
  `stable-latest`, then fast-forward `main`. There is no stable branch commit.
- A narrower request must say so explicitly: **"commit only"**, **"no
  release"**, **"local commit"**, or **"push only"**.

If publishing is blocked by the environment, report the blocker instead of
calling the task complete; the change is not delivered until the APK is out.

## Working rules

- Small focused changes, one concern per commit.
- "Commit" means commit and release as defined above. A change that no APK
  carries is not delivered.
- Run analyze and the relevant tests (or a build) before saying done.
- Ask before deleting files or changing dependencies (pubspec.yaml/lock).
- Never commit secrets, keystores, .env, private datasets or build output; scan with Gitleaks before releases.
