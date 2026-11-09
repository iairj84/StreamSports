"""Cut a beta release in one run: bump, build, audit, publish, mirror.

Usage: python3 tools/cut_release.py --notes-file NOTES.txt

Steps, stopping at the first failure:
  1. Bump the patch version and build number in pubspec.yaml.
  2. Add the notes as a new CHANGELOG.md section.
  3. flutter build apk --release --target-platform android-arm,android-arm64
  4. Audit the APK with tools/audit_apk.py; findings need --accept-audit-findings.
  5. Commit the two edited files, create the annotated tag, push both.
  6. Publish a prerelease holding the versioned APK.
  7. Refresh the rolling beta-latest release (tools/publish_beta_mirror.py).

Options: --dry-run prints the plan and writes nothing; --skip-build reuses the
APK already under build/; --local stops after the commit and tag; --version and
--build override the bump; --accept-audit-findings records findings you have
reviewed.

Refuses to start while tracked source changes are uncommitted, because those
would be left out of the release commit. The generated desktop registrant files
a build rewrites are restored rather than committed. Needs the same GitHub token
as the mirror tool: GITHUB_TOKEN in the ignored `.env` or the Git credential
helper.
"""
import argparse
import datetime
import hashlib
import re
from pathlib import Path
import shutil
import subprocess
import urllib.parse
import zipfile

from audit_apk import inspect_apk
from audit_repository import private_values
from publish_beta_mirror import (API, call, failure, github_token,
                                 latest_download_url, parse_pubspec_version, publish,
                                 repository_slug)

BUILD_COMMAND = 'flutter build apk --release --target-platform android-arm,android-arm64'
APK = Path('build/app/outputs/flutter-apk/app-release.apk')

# A build rewrites these with platform line endings; restore them before committing.
GENERATED = {
    'linux/flutter/generated_plugin_registrant.cc',
    'linux/flutter/generated_plugin_registrant.h',
    'linux/flutter/generated_plugins.cmake',
    'macos/Flutter/GeneratedPluginRegistrant.swift',
}


def read_text(path):
    """Read text without letting Python rewrite the file's line endings."""
    with Path(path).open('r', encoding='utf-8', newline='') as handle:
        return handle.read()


def write_text(path, text):
    with Path(path).open('w', encoding='utf-8', newline='') as handle:
        handle.write(text)


def newline_of(text):
    return '\r\n' if '\r\n' in text else '\n'


def next_release_version(version, build):
    """Patch bump plus one build number: `0.2.18`, 2511 -> `0.2.19`, 2512."""
    parts = version.split('.')
    if len(parts) != 3 or not all(part.isdigit() for part in parts):
        raise ValueError(f'Cannot bump the version {version!r}; pass --version and --build.')
    return f'{parts[0]}.{parts[1]}.{int(parts[2]) + 1}', build + 1


def bump_pubspec(text, version, build):
    """Rewrite the version line, keeping the file's own line ending."""
    pattern = re.compile(r'^(version:[ \t]*)[0-9][^\r\n]*(\r?)$', re.MULTILINE)
    updated, count = pattern.subn(
        lambda match: f'{match.group(1)}{version}+{build}{match.group(2)}', text, count=1)
    if count != 1:
        raise ValueError('pubspec.yaml has no version line to bump.')
    return updated


def tag_name(version, build):
    return f'v{version}-{build}'


def asset_name(version, build):
    return f'StreamSports-{version}-{build}-beta.apk'


def release_title(version):
    return f'StreamSports {version} beta'


def version_label(version, build):
    return f'{version} ({build})'


def note_bullets(text):
    """One changelog bullet per non-empty line; a leading dash is optional."""
    bullets = []
    for raw in (text or '').splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith(('- ', '* ')):
            line = line[2:].strip()
        if line:
            bullets.append(line)
    if not bullets:
        raise ValueError('Release notes are empty. Pass --notes or --notes-file.')
    return bullets


def changelog_entry(version, date, notes):
    """`## 0.2.19 — 8 November 2026` followed by the bullets, as the file writes them."""
    newline = '\n'
    heading = f'## {version} — {date}'
    body = [f'- {note}' for note in notes]
    return newline.join([heading, ''] + body) + newline + newline


def insert_changelog_entry(text, entry):
    """Place the new section under `# Changelog`, above the previous release."""
    newline = newline_of(text)
    start = text.find('# Changelog')
    if start < 0:
        raise ValueError('CHANGELOG.md has no "# Changelog" heading.')
    position = text.find(newline, start)
    if position < 0:
        return text + newline + newline + entry
    position += len(newline)
    while text.startswith(newline, position):
        position += len(newline)
    return text[:position] + entry.replace('\n', newline) + text[position:]


def release_body(repository, version, build, notes, asset, size, digest):
    lines = [f'StreamSports {version} beta, build {build}.', '']
    lines += [f'- {note}' for note in notes]
    lines += [
        '',
        '## Installing',
        '',
        f'Download `{asset}` below and open it on the device, or sideload it with '
        f'`adb install -r {asset}`. It installs over the previous build without losing '
        'playlists or settings.',
        '',
        'This release is a prerelease, so the stable address keeps serving the newest beta:',
        '',
        latest_download_url(repository),
        '',
        '## Checksum',
        '',
        f'SHA-256  {digest}',
        '',
        f'{size} bytes',
    ]
    return '\n'.join(lines)


def git(root, *arguments, check=True):
    result = subprocess.run(['git', *arguments], cwd=root, capture_output=True,
                            text=True, check=False)
    if check and result.returncode != 0:
        raise ValueError(f"git {arguments[0]} failed: {result.stderr.strip()}")
    return result


def uncommitted_paths(root):
    """Tracked changes a release commit would silently leave behind."""
    paths = []
    for line in git(root, 'status', '--porcelain').stdout.splitlines():
        if line.startswith('??'):
            continue
        path = line[3:].strip().strip('"')
        if path in GENERATED:
            continue
        paths.append(path)
    return paths


def build(root):
    executable = shutil.which('bash')
    if executable is None:
        raise ValueError('bash is required to run the Flutter build.')
    print(f'$ {BUILD_COMMAND}')
    if subprocess.run([executable, '-c', BUILD_COMMAND], cwd=root).returncode != 0:
        raise ValueError('The release build failed.')


def audit(root, apk):
    try:
        result = inspect_apk(apk, private_values(root))
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile) as error:
        raise ValueError(f'Cannot audit {apk.name}.') from error
    print(f"APK: {result['apk_bytes']} bytes, {result['entry_count']} entries, "
          f"runtimes {', '.join(result['complete_abis']) or 'none'}")
    for item in result['findings'][:50]:
        print(f"  {item['entry']}:{item['line']} [{item['rule']}]")
    return result


def restore_generated(root):
    present = [path for path in GENERATED if (root / path).exists()]
    if present:
        git(root, 'checkout', '--', *present, check=False)


def publish_versioned(token, repository, tag, title, body, apk, asset):
    """Create the prerelease and attach the APK, then read back what GitHub stored."""
    status, existing = call(token, f'{API}/repos/{repository}/releases/tags/{tag}')
    if status == 200:
        raise ValueError(f'{tag} already has a release; nothing was published.')
    if status != 404:
        raise failure('look up the release tag', status, existing)
    status, release = call(token, f'{API}/repos/{repository}/releases', 'POST', {
        'tag_name': tag, 'name': title, 'body': body,
        'draft': False, 'prerelease': True})
    if status not in (200, 201):
        raise failure('create the release', status, release)
    data = apk.read_bytes()
    upload = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(asset)
    status, uploaded = call(token, upload, 'POST', body=data,
                            content_type='application/vnd.android.package-archive')
    if status not in (200, 201):
        raise failure('upload the APK', status, uploaded)
    if uploaded.get('state') != 'uploaded' or uploaded.get('size') != len(data):
        raise ValueError('GitHub did not store the APK intact.')
    return release, uploaded


def cut(root, args):
    pubspec_path = root / 'pubspec.yaml'
    changelog_path = root / 'CHANGELOG.md'
    pubspec = read_text(pubspec_path)
    version, build_number = parse_pubspec_version(pubspec)
    if args.version or args.build is not None:
        version = args.version or version
        build_number = build_number if args.build is None else args.build
    else:
        version, build_number = next_release_version(version, build_number)
    tag = tag_name(version, build_number)
    asset = asset_name(version, build_number)
    notes = note_bullets(args.notes if args.notes is not None else
                         (read_text(args.notes_file) if args.notes_file else ''))
    date = args.date or f'{datetime.date.today().day} {datetime.date.today():%B %Y}'
    repository = args.repository
    if repository is None:
        remote = git(root, 'remote', 'get-url', 'origin', check=False).stdout
        if not remote.strip():
            raise ValueError('No origin remote; pass --repository owner/name.')
        repository = repository_slug(remote)

    if git(root, 'tag', '--list', tag).stdout.strip():
        raise ValueError(f'The tag {tag} already exists.')
    leftover = uncommitted_paths(root)
    if leftover and not args.dry_run:
        raise ValueError('Uncommitted tracked changes would be left out of the release: '
                         + ', '.join(leftover))

    if args.dry_run:
        print(f'Release plan for {version_label(version, build_number)}')
        print(f'  tag             {tag}')
        print(f'  title           {release_title(version)}')
        print(f'  asset           {asset}')
        print(f'  changelog       ## {version} — {date} ({len(notes)} bullet(s))')
        print(f'  commit          Release {version_label(version, build_number)}')
        print(f'  build           {"reuse existing APK" if args.skip_build else BUILD_COMMAND}')
        print('  audit           tools/audit_apk.py'
              + (' (findings accepted)' if args.accept_audit_findings else ''))
        print(f'  publish         prerelease {tag} with {asset}')
        print('  mirror          beta-latest with StreamSports-beta.apk')
        print(f'  stable address  {latest_download_url(repository)}')
        if leftover:
            print('  warning         uncommitted tracked changes: ' + ', '.join(leftover))
        return 0

    write_text(pubspec_path, bump_pubspec(pubspec, version, build_number))
    write_text(changelog_path, insert_changelog_entry(
        read_text(changelog_path), changelog_entry(version, date, notes)))

    if not args.skip_build:
        build(root)
    apk = root / APK
    if not apk.is_file():
        raise ValueError(f'{APK} is missing; build it first or drop --skip-build.')
    result = audit(root, apk)
    if result['findings'] and not args.accept_audit_findings:
        raise ValueError(f"{len(result['findings'])} audit finding(s) need review before "
                         'publishing; pass --accept-audit-findings once you have.')
    size = result['apk_bytes']
    digest = hashlib.sha256(apk.read_bytes()).hexdigest()

    restore_generated(root)
    git(root, 'add', 'pubspec.yaml', 'CHANGELOG.md')
    git(root, 'commit', '-m', f'Release {version_label(version, build_number)}',
        '-m', '\n'.join(f'- {note}' for note in notes))
    git(root, 'tag', '-a', tag, '-m', f'StreamSports {version_label(version, build_number)}')
    print(f'Committed and tagged {tag}.')

    if args.local:
        print(f'{apk.relative_to(root)}: {size} bytes, sha256 {digest}')
        print('Stopped before pushing; push the branch and the tag when you are ready.')
        return 0

    git(root, 'push', 'origin', 'HEAD')
    git(root, 'push', 'origin', tag)
    token = github_token(root)
    body = release_body(repository, version, build_number, notes, asset, size, digest)
    release, uploaded = publish_versioned(
        token, repository, tag, release_title(version), body, apk, asset)
    print(f"Published {release['html_url']} with {uploaded['name']} "
          f"({uploaded['size']} bytes).")
    mirror = publish(root, apk, repository, token)
    print(f"Mirror {mirror['action']}: {mirror['address']} "
          f"({mirror['address_bytes']} bytes verified).")
    print(f'Released {version_label(version, build_number)}: {release["html_url"]}')
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--notes', help='release notes; one bullet per line')
    parser.add_argument('--notes-file', type=Path, help='file of bullets, one per line')
    parser.add_argument('--version', help='version to release; default bumps the patch')
    parser.add_argument('--build', type=int, help='build number; default bumps by one')
    parser.add_argument('--date', help='changelog date, for example "9 November 2026"')
    parser.add_argument('--repository', help='owner/name; defaults to the origin remote')
    parser.add_argument('--skip-build', action='store_true', help='reuse the APK under build/')
    parser.add_argument('--accept-audit-findings', action='store_true',
                        help='publish after reviewing reported audit findings')
    parser.add_argument('--local', action='store_true',
                        help='stop after the commit and tag, without pushing or publishing')
    parser.add_argument('--dry-run', action='store_true', help='print the plan and write nothing')
    args = parser.parse_args(argv)
    if not args.notes and not args.notes_file:
        parser.error('Release notes are required: --notes TEXT or --notes-file PATH.')
    try:
        return cut(Path(__file__).resolve().parents[1], args)
    except (OSError, ValueError) as error:
        print(f'Release stopped: {error}')
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
