import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publish_beta_mirror import (ASSET_NAME, DOWNLOADER_CODE, MIRROR_TAG, latest_download_url,
                                 mirror_body, parse_pubspec_version, repository_slug)


class BetaMirrorTests(unittest.TestCase):
    def test_repository_slug_from_https_and_ssh_remotes(self):
        for remote, slug in [
            ('https://github.com/iairj84/StreamSports.git', 'iairj84/StreamSports'),
            ('https://github.com/iairj84/StreamSports', 'iairj84/StreamSports'),
            ('git@github.com:iairj84/StreamSports.git', 'iairj84/StreamSports'),
            ('git@github.com:iairj84/StreamSports', 'iairj84/StreamSports'),
        ]:
            self.assertEqual(repository_slug(remote), slug)

    def test_non_github_remote_is_rejected(self):
        for remote in ('https://gitlab.com/owner/name.git', 'file:///srv/repo', ''):
            with self.assertRaises(ValueError):
                repository_slug(remote)

    def test_stable_address_uses_the_fixed_asset_name(self):
        self.assertEqual(
            latest_download_url('iairj84/StreamSports'),
            'https://github.com/iairj84/StreamSports/releases/latest/download/StreamSports-beta.apk')
        self.assertTrue(latest_download_url('owner/name').endswith('/' + ASSET_NAME))

    def test_mirror_tag_carries_no_version_number(self):
        # The updater ranks releases by the build number in the tag, so a digit
        # here would make the rolling release look like a build to install.
        self.assertFalse(any(character.isdigit() for character in MIRROR_TAG))
        self.assertRegex(MIRROR_TAG, r'^[a-z-]+$')

    def test_pubspec_version_parses_version_and_build(self):
        self.assertEqual(parse_pubspec_version('name: app\nversion: 0.2.18+2511\n'),
                         ('0.2.18', 2511))
        self.assertEqual(parse_pubspec_version('version: 1.0.0\n'), ('1.0.0', 0))

    def test_missing_version_line_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_pubspec_version('name: app\n')

    def test_body_names_the_build_checksum_and_address(self):
        digest = 'a' * 64
        body = mirror_body('iairj84/StreamSports', '0.2.18', 2511, 54014889, digest)
        self.assertIn('0.2.18 (2511)', body)
        self.assertIn(digest, body)
        self.assertIn('54014889 bytes', body)
        self.assertIn(latest_download_url('iairj84/StreamSports'), body)
        self.assertIn('beta-latest', body)
        self.assertIn(DOWNLOADER_CODE, body)
        self.assertIn('docs/install.md', body)


if __name__ == '__main__':
    unittest.main()
