# Release preparation

## Source and checks

Run the checks in [development](development.md), then scan the source with Gitleaks or an equivalent secret scanner. Review screenshots manually. Keep credentials, signing keys, private data and generated downloads out of Git.

Source audits cover the current files, not previously published commits or binaries. To create a reviewed source snapshot without Git history, preserve the licence and attribution and run:

```sh
python3 tools/export_source.py /path/outside/checkout/source-snapshot
```

The destination must be new. The exporter writes the exact bytes it audits, omits Git history and ignored files, and discards incomplete exports. File-list changes during export require a retry. It preserves executable permissions without copying local file metadata. Avoid editing the checkout while exporting.

Archives, symlinks and nested repositories require separate review; the exporter will not silently include them. Do not copy the old `.git` directory, local configuration or build output into the snapshot. Automated scans cannot establish that arbitrary images or encoded text contain no private data; retain manual review.

Adding a file to `.gitignore` does not remove it from Git. The audit also flags tracked files matching ignore rules. Review those entries and untrack local-only files before exporting; keep any needed local copies outside the snapshot.

In the snapshot directory, initialise a new history before running the Git-based source checks:

```sh
git init -b main
python3 tools/audit_repository.py
python3 -m unittest discover -s tools/tests
```

Set a public commit identity, such as a GitHub noreply address, before the first commit. Review `git status` and the staged files before connecting a new remote.

## Android APK

Daily work lands on the `beta` branch. Every release cuts from `beta`: one command performs the steps below in order — bump, changelog entry, build, audit, commit, tag, push to `beta`, the versioned beta prerelease and the rolling **beta-only** download. Stable is never touched by a cut.

```sh
git checkout beta
python3 tools/preflight.py test/<focused>_test.dart   # analyze, tests and audits together
python3 tools/cut_release.py --notes-file release-notes.txt
```

Notes are one bullet per line and become both the changelog section and the release body. The script refuses to start anywhere but `beta` (override with `--allow-any-branch` for emergencies only), refuses while tracked source changes are uncommitted, restores the generated desktop registrant files a build rewrites, and stops on audit findings unless `--accept-audit-findings` says they were reviewed. `--dry-run` prints the plan, `--skip-build` reuses the APK already under `build/`, `--local` stops after the commit and tag, and `--version`/`--build` override the automatic bump. If only the mirror step fails, rerun `python3 tools/publish_beta_mirror.py <apk>`; the versioned release is already published by then. The manual steps that follow describe the same beta release.

## Promoting a beta to stable

When a beta has survived real use, copy its exact bytes to stable — no rebuild — then fast-forward `main` to match `beta`:

```sh
python3 tools/promote_stable.py --tag v<version>-<build>
git fetch origin beta && git push origin origin/beta:main
```

Promotion republishes the versioned beta APK byte-for-byte into the rolling `stable-latest` release (`StreamSports-beta.apk`, the preserved download filename and Downloader code) and marks it GitHub latest, so `.../releases/latest/download/...` and the in-app Stable channel serve it. It never touches `beta-latest` and never rewrites the build number, so a device on beta is never offered a stable build with a lower build number. `main` only moves on promotion, so stable code always equals tested beta code.

1. Set the four signing values from `.env.example`; keep the keystore outside source. Preserve the certificate for updates. Without these values, local release builds fall back to debug signing and are not distribution builds.
2. Increase the version/build number in `pubspec.yaml`. Build from a neutral directory such as `/workspace/StreamSports` so generated source paths do not expose a personal home directory.
3. Build and verify:

```sh
flutter build apk --release --target-platform android-arm,android-arm64
python3 tools/audit_apk.py build/app/outputs/flutter-apk/app-release.apk
```

This creates one APK containing both ARM runtimes at `build/app/outputs/flutter-apk/app-release.apk`. No architecture choice is needed when installing it. The Gradle configuration keeps plugin libraries aligned with the requested Flutter targets.

The APK audit scans decompressed entries and filenames, checks for private/generated files and verifies complete Flutter runtime libraries for each packaged ABI. It reports sizes without extracting files or printing matched secrets. Review findings before distribution; the download packager now enforces this check on the exact bytes it packages.

Separately check the application ID, embedded version, signing certificate and checksum with Android build tools. The audit does not verify signatures or all manifest metadata, and cannot prove arbitrary encoded data is safe. The download manifest uses the checkout's `pubspec.yaml`, so verify that it matches the APK. Old APKs are not cleared by a clean source scan; rebuild from the final reviewed source.

## GitHub Releases

Create a version tag from the reviewed source and prepare a draft release. Attach:

- `app-release.apk`: the signed, audited APK. Keep this filename stable for the latest-download link.
- `StreamSports-source.zip`: the exact corresponding application source, without local configuration or build output.
- `android-native-sources.zip`: the pinned decoder build project, Media3 and FFmpeg source trees, licences and build instructions.
- `SHA256SUMS.txt`: SHA-256 checksums of the three files above.

Verify the draft assets before publishing. Keep betas marked as prereleases, which GitHub excludes from `latest`.

A cut refreshes the early-channel mirror automatically; to do it by hand:

```sh
python3 tools/publish_beta_mirror.py build/app/outputs/flutter-apk/app-release.apk
```

That creates or refreshes `beta-latest` holding one fixed-name asset, `StreamSports-early.apk`. It is deliberately not GitHub's latest release. Testers fetch it from:

`https://github.com/iairj84/StreamSports/releases/download/beta-latest/StreamSports-early.apk`

Stable moves only by promotion, never by rebuilding. Promote the versioned beta tag, which republishes those exact bytes to `stable-latest` as `StreamSports-beta.apk` and marks it GitHub latest:

```sh
python3 tools/promote_stable.py --tag v<version>-<build>
git fetch origin beta && git push origin origin/beta:main
```

The stable address and the Downloader code `1976156` resolve to that release:

`https://github.com/iairj84/StreamSports/releases/latest/download/StreamSports-beta.apk`

A code cannot be repointed once created, so keep the asset name and the `stable-latest` release in place and refresh it with the tool rather than publishing under a new name. Promotion writes the version and build named by the versioned tag, not the promoting checkout's `pubspec.yaml`, so it is safe to run from an older `main` before the fast-forward.

Rolling tags carry no version number on purpose: the in-app updater resolves both channels by tag and reads the build from the mirror body, so `beta-latest` is never mistaken for an installable build. `publish_beta_mirror.py` republishes the exact bytes it was given and, for stable, downloads the address again to compare checksums. Neither tool audits or signs the APK, so run `tools/audit_apk.py` and the signature checks first. A normal release with `app-release.apk` keeps resolving at `.../releases/latest/download/app-release.apk`. The [installation guide](install.md) describes phone/TV installation and optional Downloader codes.

## Distribution

Publish the exact corresponding application and native-library sources, build scripts and notices alongside each binary. Use the [dependency inventory](dependencies/README.md); the Jellyfin sources JAR alone omits FFmpeg. Desktop builds are no longer included.

For a split-file web download, use:

```sh
python3 tools/package_preview_download.py APK_PATH --output-dir OUTPUT_DIRECTORY
```

Keep that output outside source. Verify the downloaded checksum and retain the intended access controls. Use your own branding and relay infrastructure.

[Current release review](release-readiness.md) · [Licence and attribution](../NOTICE.md)
