"""Publish the rolling beta download that keeps one stable address current.

GitHub's latest-download address excludes prereleases, and this project ships
betas as prereleases. This tool maintains a non-prerelease release tagged
`beta-latest` holding a single fixed-name APK, so this address always resolves
to the newest build:

    https://github.com/iairj84/StreamSports/releases/latest/download/StreamSports-beta.apk

Running it again replaces that asset, so the address never changes and stays
safe to shorten for Downloader. The tag deliberately carries no version
number: the app's updater ranks releases by the build number in the tag, so
`beta-latest` is never offered as an update.

It publishes bytes; it does not audit or sign them. Run tools/audit_apk.py and
the signature checks first.

Usage: python3 tools/publish_beta_mirror.py APK_PATH [--dry-run]

Needs a GitHub token with contents: write, taken from GITHUB_TOKEN in the
ignored `.env`/environment or from the local Git credential helper. The token
is never printed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import zipfile

from local_config import local_setting

MIRROR_TAG = 'beta-latest'
ASSET_NAME = 'StreamSports-beta.apk'
RELEASE_NAME = 'StreamSports beta, always the newest build'
API = 'https://api.github.com'
CHUNK = 1024 * 1024


def repository_slug(remote):
    """`https://github.com/owner/name.git` or `git@github.com:owner/name` -> `owner/name`."""
    match = re.search(r'github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/*$', remote.strip())
    if not match:
        raise ValueError('The origin remote is not a GitHub repository; pass --repository.')
    return f'{match.group(1)}/{match.group(2)}'


def parse_pubspec_version(text):
    """Return `(version, build)` from the checkout's pubspec version line."""
    line = next((item for item in text.splitlines() if item.startswith('version:')), None)
    if line is None:
        raise ValueError('pubspec.yaml has no version line.')
    version, _, build = line.split(':', 1)[1].strip().partition('+')
    return version.strip(), int(build.strip() or 0)


def latest_download_url(repository, asset=ASSET_NAME):
    return f'https://github.com/{repository}/releases/latest/download/{asset}'


def mirror_body(repository, version, build, size, digest):
    """Release text for the rolling release: what it is, plus exactly what it holds."""
    label = f'{version} ({build})' if build else version
    return '\n'.join([
        'Rolling download for the newest StreamSports beta.',
        '',
        'This release exists to keep one stable address working. The versioned '
        'beta and its release notes are published separately as a prerelease.',
        '',
        f'- Build: {label}',
        f'- Size: {size} bytes',
        f'- SHA-256: {digest}',
        '',
        latest_download_url(repository),
        '',
        'Do not edit the `beta-latest` tag or its asset name. The app ranks '
        'updates by the build number in the tag, so this one carries none, and '
        'the fixed asset name is what the stable address resolves to.',
    ])


def github_token(root):
    token = local_setting(root, 'GITHUB_TOKEN')
    if token:
        return token
    result = subprocess.run(
        ['git', 'credential', 'fill'], cwd=root,
        input='protocol=https\nhost=github.com\n\n',
        capture_output=True, text=True, check=False)
    for line in result.stdout.splitlines():
        if line.startswith('password=') and line[len('password='):].strip():
            return line[len('password='):].strip()
    raise ValueError(
        'No GitHub token. Set GITHUB_TOKEN in the ignored .env or sign in with '
        'the Git credential helper.')


def call(token, url, method='GET', payload=None, body=None,
         content_type='application/json'):
    """Send one GitHub request and return `(status, decoded body)`."""
    data = body if body is not None else (
        json.dumps(payload).encode() if payload is not None else None)
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header('Authorization', f'token {token}')
    request.add_header('Accept', 'application/vnd.github+json')
    request.add_header('User-Agent', 'StreamSports-beta-mirror')
    request.add_header('Content-Type', content_type)
    try:
        with urllib.request.urlopen(request, timeout=300) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            decoded = json.loads(raw) if raw else {}
        except ValueError:
            decoded = {}
        return error.code, decoded


def failure(action, status, response):
    message = response.get('message', '') if isinstance(response, dict) else ''
    return ValueError(f'Cannot {action} ({status}){": " + message if message else "."}')


def read_apk(apk):
    """Return the exact bytes to publish after confirming they are an APK."""
    data = apk.read_bytes()
    try:
        with zipfile.ZipFile(apk) as archive:
            names = set(archive.namelist())
    except zipfile.BadZipFile as error:
        raise ValueError(f'{apk.name} is not a readable package.') from error
    if not {'AndroidManifest.xml', 'classes.dex'} <= names:
        raise ValueError(f'{apk.name} is not an Android application package.')
    return data


def publish(root, apk, repository, token, verify=True):
    """Create or refresh the mirror release, then confirm the stable address."""
    data = read_apk(apk)
    digest = hashlib.sha256(data).hexdigest()
    version, build = parse_pubspec_version((root / 'pubspec.yaml').read_text())
    body = mirror_body(repository, version, build, len(data), digest)
    payload = {'name': RELEASE_NAME, 'body': body, 'draft': False,
               'prerelease': False, 'make_latest': 'true'}
    status, release = call(token, f'{API}/repos/{repository}/releases/tags/{MIRROR_TAG}')
    if status == 200:
        status, release = call(token, f'{API}/repos/{repository}/releases/{release["id"]}',
                               'PATCH', payload)
        if status != 200:
            raise failure('update the mirror release', status, release)
        action = 'updated'
    elif status == 404:
        payload.update({'tag_name': MIRROR_TAG, 'target_commitish': 'main'})
        status, release = call(token, f'{API}/repos/{repository}/releases', 'POST', payload)
        if status not in (200, 201):
            raise failure('create the mirror release', status, release)
        action = 'created'
    else:
        raise failure('read the mirror release', status, release)
    for asset in release.get('assets', []):
        if asset.get('name') == ASSET_NAME:
            status, removed = call(
                token, f'{API}/repos/{repository}/releases/assets/{asset["id"]}', 'DELETE')
            if status != 204:
                raise failure('replace the published asset', status, removed)
    upload = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(ASSET_NAME)
    status, asset = call(token, upload, 'POST', body=data,
                         content_type='application/vnd.android.package-archive')
    if status not in (200, 201):
        raise failure('upload the fixed-name asset', status, asset)
    status, latest = call(token, f'{API}/repos/{repository}/releases/latest')
    if status != 200:
        raise failure('read the latest release', status, latest)
    if latest.get('tag_name') != MIRROR_TAG:
        raise ValueError(
            f'GitHub reports {latest.get("tag_name")} as the latest release, not {MIRROR_TAG}.')
    result = {'action': action, 'release': release['html_url'], 'asset': asset.get('name'),
              'bytes': len(data), 'sha256': digest,
              'address': latest_download_url(repository), 'address_bytes': None}
    if not verify:
        return result
    request = urllib.request.Request(
        result['address'], headers={'User-Agent': 'StreamSports-beta-mirror'})
    published = hashlib.sha256()
    received = 0
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            for chunk in iter(lambda: response.read(CHUNK), b''):
                published.update(chunk)
                received += len(chunk)
    except urllib.error.URLError as error:
        raise ValueError(f'The stable address did not serve the APK: {error}') from error
    if published.hexdigest() != digest:
        raise ValueError('The stable address serves different bytes than the input APK.')
    result['address_bytes'] = received
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--repository', help='owner/name; defaults to the origin remote')
    parser.add_argument('--dry-run', action='store_true',
                        help='report what would be published without calling GitHub')
    parser.add_argument('--no-verify', action='store_true',
                        help='skip downloading the stable address to compare checksums')
    args = parser.parse_args(argv)
    if not args.apk.is_file():
        parser.error('APK not found. Build it first and pass its path.')
    root = Path(__file__).resolve().parents[1]
    if args.repository:
        repository = args.repository
    else:
        try:
            remote = subprocess.run(['git', 'remote', 'get-url', 'origin'], cwd=root,
                                    capture_output=True, text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError):
            remote = ''
        if not remote.strip():
            parser.error('No origin remote; pass --repository owner/name.')
        repository = repository_slug(remote)
    try:
        if args.dry_run:
            data = read_apk(args.apk)
            version, build = parse_pubspec_version((root / 'pubspec.yaml').read_text())
            print(f'Would publish {len(data)} bytes of {args.apk.name} as {ASSET_NAME} in '
                  f'{MIRROR_TAG} for build {version} ({build}), sha256 '
                  f'{hashlib.sha256(data).hexdigest()}.')
            print(f'Stable address: {latest_download_url(repository)}')
            return 0
        result = publish(root, args.apk, repository, github_token(root),
                         verify=not args.no_verify)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"{result['action']} {MIRROR_TAG}: {result['asset']} ({result['bytes']} bytes), "
          f"sha256 {result['sha256']}")
    print(f"Release: {result['release']}")
    print(f"Stable address: {result['address']}")
    if result['address_bytes'] is None:
        print('Skipped the published-address check.')
    else:
        print(f"Verified: the address served {result['address_bytes']} bytes with the same checksum.")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
