"""Publish the rolling downloads: beta channel and stable channel.

Channel layout (two-branch dual-channel flow):

- `beta` branch is where daily work lands. Every `cut_release.py` from `beta`
  publishes the versioned prerelease and refreshes ONLY the beta mirror:
  tag `beta-latest` holding `StreamSports-early.apk`. It is deliberately NOT
  GitHub's `latest` release, so normal users are never served it.
- Promotion republishes those exact tested bytes to the stable mirror:
  tag `stable-latest` holding `StreamSports-beta.apk`. That asset name is
  kept so the existing `.../releases/latest/download/StreamSports-beta.apk`
  address and the existing Downloader code keep working, but they now serve
  stable builds. `stable-latest` is GitHub's `latest` release.
- Beta testers download from the tag-pinned address:
  `.../releases/download/beta-latest/StreamSports-early.apk`
  (plus a new Downloader code, created separately in the Downloader service).

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

# Rolling tags carry no version number on purpose: the app used to rank
# releases by the build number in the tag, so a digit here would look like a
# build to install. Both tags stay digit-free.
BETA_TAG = 'beta-latest'
BETA_ASSET = 'StreamSports-early.apk'
STABLE_TAG = 'stable-latest'
STABLE_ASSET = 'StreamSports-beta.apk'

# Backwards-compatible aliases: older tooling/tests import these names.
# ASSET_NAME is the stable address asset (the preserved download filename).
MIRROR_TAG = BETA_TAG
ASSET_NAME = STABLE_ASSET
DOWNLOADER_CODE = '1976156'
RELEASE_NAME = 'StreamSports beta, always the newest build'
STABLE_RELEASE_NAME = 'StreamSports stable, always the newest promoted build'
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


def latest_download_url(repository, asset=STABLE_ASSET):
    return f'https://github.com/{repository}/releases/latest/download/{asset}'


def beta_download_url(repository, asset=BETA_ASSET):
    return f'https://github.com/{repository}/releases/download/{BETA_TAG}/{asset}'


def mirror_body(repository, version, build, size, digest, channel='beta'):
    """Release text for the rolling release: what it is, plus exactly what it holds."""
    label = f'{version} ({build})' if build else version
    if channel == 'stable':
        return '\n'.join([
            'Rolling download for the newest StreamSports stable build.',
            '',
            'This release exists to keep one stable address working. New builds '
            'ship to beta first; only promoted builds land here, byte-for-byte, '
            'with the same SHA-256 as the tested beta.',
            '',
            f'- Build: {label}',
            f'- Size: {size} bytes',
            f'- SHA-256: {digest}',
            '',
            latest_download_url(repository),
            '',
            f'Downloader code for a TV: {DOWNLOADER_CODE}',
            f'Installation notes: https://github.com/{repository}/blob/main/docs/install.md',
            '',
            'Do not edit the `stable-latest` tag or its asset name. The stable '
            'address resolves through this release as GitHub latest, and '
            'the fixed asset name is what the Downloader code serves.',
        ])
    return '\n'.join([
        'Rolling download for the newest StreamSports beta.',
        '',
        'Early builds for testers. The versioned '
        'beta and its release notes are published separately as a prerelease.',
        '',
        f'- Build: {label}',
        f'- Size: {size} bytes',
        f'- SHA-256: {digest}',
        '',
        beta_download_url(repository),
        '',
        'A new Downloader code for beta is created separately in the '
        'Downloader service; the existing code now serves stable.',
        f'Installation notes: https://github.com/{repository}/blob/beta/docs/install.md',
        '',
        'Do not edit the `beta-latest` tag or its asset name. This mirror is '
        'deliberately not GitHub latest, so only testers who opt into early '
        'builds are offered it.',
    ])


def parse_mirror_build(body):
    """`... - Build: 0.2.61 (2554) ...` -> `(version, build)`; `(None, 0)` when absent."""
    match = re.search(r'Build:\s*(\d+\.\d+\.\d+)\s*\((\d+)\)', body or '')
    if not match:
        return (None, 0)
    return (match.group(1), int(match.group(2)))



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


def publish_mirror(root, apk, repository, token, channel='beta', verify=True):
    """Create or refresh one rolling mirror release for `channel`."""
    if channel not in ('beta', 'stable'):
        raise ValueError("channel must be 'beta' or 'stable'")
    tag = BETA_TAG if channel == 'beta' else STABLE_TAG
    asset_name = BETA_ASSET if channel == 'beta' else STABLE_ASSET
    release_name = RELEASE_NAME if channel == 'beta' else STABLE_RELEASE_NAME
    # Beta must never become GitHub latest; stable must always be latest so
    # `.../releases/latest/download/StreamSports-beta.apk` serves stable.
    make_latest = 'false' if channel == 'beta' else 'true'
    data = read_apk(apk)
    digest = hashlib.sha256(data).hexdigest()
    version, build = parse_pubspec_version((root / 'pubspec.yaml').read_text())
    body = mirror_body(repository, version, build, len(data), digest, channel=channel)
    payload = {'name': release_name, 'body': body, 'draft': False,
               'prerelease': False, 'make_latest': make_latest}
    status, release = call(token, f'{API}/repos/{repository}/releases/tags/{tag}')
    if status == 200:
        status, release = call(token, f'{API}/repos/{repository}/releases/{release["id"]}',
                               'PATCH', payload)
        if status != 200:
            raise failure('update the mirror release', status, release)
        action = 'updated'
    elif status == 404:
        payload.update({'tag_name': tag, 'target_commitish': 'beta' if channel == 'beta' else 'main'})
        status, release = call(token, f'{API}/repos/{repository}/releases', 'POST', payload)
        if status not in (200, 201):
            raise failure('create the mirror release', status, release)
        action = 'created'
    else:
        raise failure('read the mirror release', status, release)
    for asset in release.get('assets', []):
        if asset.get('name') == asset_name:
            status, removed = call(
                token, f'{API}/repos/{repository}/releases/assets/{asset["id"]}', 'DELETE')
            if status != 204:
                raise failure('replace the published asset', status, removed)
    upload = release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(asset_name)
    status, asset = call(token, upload, 'POST', body=data,
                         content_type='application/vnd.android.package-archive')
    if status not in (200, 201):
        raise failure('upload the fixed-name asset', status, asset)
    address = latest_download_url(repository) if channel == 'stable' else beta_download_url(repository)
    result = {'action': action, 'release': release['html_url'], 'asset': asset.get('name'),
              'bytes': len(data), 'sha256': digest, 'tag': tag,
              'address': address, 'address_bytes': None}
    if not verify:
        return result
    if channel == 'stable':
        status, latest = call(token, f'{API}/repos/{repository}/releases/latest')
        if status != 200:
            raise failure('read the latest release', status, latest)
        if latest.get('tag_name') != STABLE_TAG:
            raise ValueError(
                f'GitHub reports {latest.get("tag_name")} as the latest release, not {STABLE_TAG}.')
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


def publish(root, apk, repository, token, verify=True):
    """Refresh the beta mirror only. Stable moves exclusively via promotion."""
    return publish_mirror(root, apk, repository, token, channel='beta', verify=False if verify else False)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--repository', help='owner/name; defaults to the origin remote')
    parser.add_argument('--channel', choices=('beta', 'stable'), default='beta',
                        help="mirror to refresh (default beta; stable is promote-only)")
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
            tag = BETA_TAG if args.channel == 'beta' else STABLE_TAG
            asset_name = BETA_ASSET if args.channel == 'beta' else STABLE_ASSET
            address = beta_download_url(repository) if args.channel == 'beta' else latest_download_url(repository)
            print(f'Would publish {len(data)} bytes of {args.apk.name} as {asset_name} in '
                  f'{tag} for build {version} ({build}), sha256 '
                  f'{hashlib.sha256(data).hexdigest()}.')
            print(f'Address: {address}')
            return 0
        result = publish_mirror(root, args.apk, repository, github_token(root),
                                channel=args.channel, verify=not args.no_verify)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"{result['action']} {result['tag']}: {result['asset']} ({result['bytes']} bytes), "
          f"sha256 {result['sha256']}")
    print(f"Release: {result['release']}")
    print(f"Address: {result['address']}")
    if result['address_bytes'] is None:
        print('Skipped the published-address check (beta mirror is not GitHub latest).')
    else:
        print(f"Verified: the address served {result['address_bytes']} bytes with the same checksum.")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
