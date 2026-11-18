import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from publish_beta_mirror import (BETA_ASSET, BETA_TAG, STABLE_ASSET, STABLE_TAG,
                                 beta_download_url, latest_download_url,
                                 mirror_body, parse_mirror_build, parse_pubspec_version,
                                 repository_slug)


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

    def test_stable_address_keeps_the_existing_asset_name(self):
        self.assertEqual(STABLE_ASSET, 'StreamSports-beta.apk')
        self.assertEqual(
            latest_download_url('iairj84/StreamSports'),
            'https://github.com/iairj84/StreamSports/releases/latest/download/StreamSports-beta.apk')
        self.assertTrue(latest_download_url('owner/name').endswith('/' + STABLE_ASSET))

    def test_beta_moves_to_its_own_tag_and_asset(self):
        self.assertEqual(BETA_TAG, 'beta-latest')
        self.assertEqual(STABLE_TAG, 'stable-latest')
        self.assertNotEqual(BETA_ASSET, STABLE_ASSET)
        self.assertIn(BETA_TAG, beta_download_url('owner/name'))
        self.assertIn(BETA_ASSET, beta_download_url('owner/name'))

    def test_mirror_tags_carry_no_version_number(self):
        # The updater used to rank releases by the build number in the tag,
        # so a digit here would look like a build to install. Rolling tags
        # stay digit-free; the build comes from the mirror body instead.
        for tag in (BETA_TAG, STABLE_TAG):
            self.assertFalse(any(character.isdigit() for character in tag))
            self.assertRegex(tag, r'^[a-z-]+$')

    def test_pubspec_version_parses_version_and_build(self):
        self.assertEqual(parse_pubspec_version('name: app\nversion: 0.2.18+2511\n'),
                         ('0.2.18', 2511))
        self.assertEqual(parse_pubspec_version('version: 1.0.0\n'), ('1.0.0', 0))

    def test_missing_version_line_is_rejected(self):
        with self.assertRaises(ValueError):
            parse_pubspec_version('name: app\n')

    def test_beta_body_names_the_build_and_tag_pinned_address(self):
        digest = 'a' * 64
        body = mirror_body('iairj84/StreamSports', '0.2.18', 2511, 54014889, digest,
                           channel='beta')
        self.assertIn('0.2.18 (2511)', body)
        self.assertIn(digest, body)
        self.assertIn('54014889 bytes', body)
        self.assertIn(beta_download_url('iairj84/StreamSports'), body)
        self.assertIn('beta-latest', body)

    def test_stable_body_names_the_build_checksum_and_stable_address(self):
        digest = 'a' * 64
        body = mirror_body('iairj84/StreamSports', '0.2.18', 2511, 54014889, digest,
                           channel='stable')
        self.assertIn('0.2.18 (2511)', body)
        self.assertIn(digest, body)
        self.assertIn('54014889 bytes', body)
        self.assertIn(latest_download_url('iairj84/StreamSports'), body)
        self.assertIn('stable-latest', body)

    def test_mirror_build_parses_the_body(self):
        body = mirror_body('o/n', '0.2.61', 2554, 10, 'd' * 64, channel='stable')
        self.assertEqual(parse_mirror_build(body), ('0.2.61', 2554))
        self.assertEqual(parse_mirror_build('no build here'), (None, 0))


if __name__ == '__main__':
    unittest.main()
