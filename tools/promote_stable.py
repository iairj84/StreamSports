"""Promote a tested beta build to stable without rebuilding.

Copies the exact APK bytes from the versioned beta prerelease (tag
`v<version>-<build>`) into the rolling `stable-latest` mirror as
`StreamSports-beta.apk` — the preserved filename behind
`.../releases/latest/download/StreamSports-beta.apk` and the existing
Downloader code. Marks `stable-latest` as GitHub latest so normal users are
served it. Never touches `beta-latest`.

Usage:
  python3 tools/promote_stable.py --tag v0.2.61-2554 [--dry-run]
  python3 tools/promote_stable.py --tag v0.2.61-2554 --local-file path/to.apk --dry-run

Needs a GitHub token with contents: write (GITHUB_TOKEN in ignored `.env`
or the Git credential helper). After promoting releases, fast-forward main:
  git fetch origin beta && git push origin origin/beta:main   # fast-forward only
"""
import argparse
import hashlib
import tempfile
from pathlib import Path
import urllib.request

from publish_beta_mirror import (API, STABLE_ASSET, STABLE_TAG, call, failure,
                                 github_token, latest_download_url,
                                 parse_versioned_tag, publish_mirror, read_apk,
                                 repository_slug)


def versioned_asset_name(version, build):
    return f'StreamSports-{version}-{build}-beta.apk'


def download_versioned_apk(token, repository, tag, dest):
    status, release = call(token, f'{API}/repos/{repository}/releases/tags/{tag}')
    if status != 200:
        raise failure(f'read versioned release {tag}', status, release)
    if release.get('draft') is True:
        raise ValueError(f'{tag} is a draft release; promote only published betas.')
    assets = [a for a in release.get('assets', []) if isinstance(a, dict)]
    apk = next((a for a in assets if (a.get('name') or '').lower().endswith('.apk')), None)
    if apk is None or not apk.get('url'):
        raise ValueError(f'{tag} has no APK asset to promote.')
    request = urllib.request.Request(
        apk['url'],
        headers={'Authorization': f'token {token}',
                 'Accept': 'application/octet-stream',
                 'User-Agent': 'StreamSports-promote-stable'})
    digest = hashlib.sha256()
    size = 0
    with urllib.request.urlopen(request, timeout=600) as response, dest.open('wb') as out:
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
            digest.update(chunk)
            size += len(chunk)
    return {'release': release, 'asset': apk, 'size': size, 'sha256': digest.hexdigest()}


def promote(root, repository, token, tag, local_file=None, verify=True):
    # The tag names the bytes being promoted, so it is also the only safe
    # source of the mirror body's version/build. Reading the checkout pubspec
    # used to stamp an older build when promotion ran from a stale main.
    version_build = parse_versioned_tag(tag)
    if local_file is not None:
        data = read_apk(Path(local_file))
        info = {'size': len(data), 'sha256': hashlib.sha256(data).hexdigest(), 'local': True}
        with tempfile.TemporaryDirectory() as tmp:
            staged = Path(tmp) / STABLE_ASSET
            staged.write_bytes(data)
            result = publish_mirror(root, staged, repository, token,
                                    channel='stable', verify=False,
                                    version_build=version_build)
        result.update({'tag': tag, 'bytes': info['size'], 'sha256': info['sha256']})
        return result
    with tempfile.TemporaryDirectory() as tmp:
        dest = Path(tmp) / STABLE_ASSET
        info = download_versioned_apk(token, repository, tag, dest)
        # Guard: the staged file must be a real APK before it can move stable.
        read_apk(dest)
        result = publish_mirror(root, dest, repository, token,
                                channel='stable', verify=verify,
                                version_build=version_build)
        result.update({'promoted_tag': tag,
                       'promoted_asset': info['asset'].get('name'),
                       'bytes': info['size'], 'sha256': info['sha256']})
        return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--tag', required=True, help='versioned beta tag, e.g. v0.2.61-2554')
    parser.add_argument('--repository', help='owner/name; defaults to the origin remote')
    parser.add_argument('--local-file', type=Path,
                        help='promote this local APK instead of downloading the release')
    parser.add_argument('--no-verify', action='store_true')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    root = Path(__file__).resolve().parents[1]
    if args.repository:
        repository = args.repository
    else:
        import subprocess
        try:
            remote = subprocess.run(['git', 'remote', 'get-url', 'origin'], cwd=root,
                                    capture_output=True, text=True, check=True).stdout
        except Exception:
            remote = ''
        if not remote.strip():
            parser.error('No origin remote; pass --repository owner/name.')
        repository = repository_slug(remote)
    if args.dry_run:
        print(f'Would promote {args.tag} to {STABLE_TAG} as {STABLE_ASSET}.')
        print(f'Stable address: {latest_download_url(repository)}')
        print('Then fast-forward main: git fetch origin beta && git push origin origin/beta:main')
        version, build = parse_versioned_tag(args.tag)
        print(f'Tag build: {version} ({build})')
        return 0
    try:
        token = github_token(root)
        result = promote(root, repository, token, args.tag,
                         local_file=args.local_file, verify=not args.no_verify)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(f"Promoted {args.tag} -> {STABLE_TAG}: {result.get('asset')} "
          f"({result.get('bytes')} bytes), sha256 {result.get('sha256')}")
    print(f"Release: {result.get('release')}")
    print(f"Stable address: {latest_download_url(repository)}")
    print('Next: git fetch origin beta && git push origin origin/beta:main (fast-forward only)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
