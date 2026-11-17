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

## Working rules

- Small focused changes, one concern per commit.
- Run analyze and the relevant tests (or a build) before saying done.
- Ask before deleting files or changing dependencies (pubspec.yaml/lock).
- Never commit secrets, keystores, .env, private datasets or build output; scan with Gitleaks before releases.
