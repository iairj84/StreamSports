import sys
import tempfile
import zipfile
from pathlib import Path
from unittest import mock
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import promote_stable
from promote_stable import versioned_asset_name
from publish_beta_mirror import parse_versioned_tag


def _fake_apk(path):
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('AndroidManifest.xml', '<manifest/>')
        archive.writestr('classes.dex', 'dex')


class PromoteStableTests(unittest.TestCase):
    def test_versioned_asset_name_matches_cut_release(self):
        self.assertEqual(versioned_asset_name('0.2.61', 2554),
                         'StreamSports-0.2.61-2554-beta.apk')

    def test_versioned_tag_names_the_build_being_promoted(self):
        self.assertEqual(parse_versioned_tag('v0.2.74-2567'), ('0.2.74', 2567))
        self.assertEqual(parse_versioned_tag(' v1.2.3-4 '), ('1.2.3', 4))
        for bad in ('stable-latest', 'beta-latest', 'v0.2.74', '0.2.74-2567',
                    'v0.2-2567', 'v0.2.74-0x1'):
            with self.assertRaises(ValueError, msg=bad):
                parse_versioned_tag(bad)

    def test_promotion_stamps_the_tag_not_the_checkout(self):
        # The regression: promoting from an old main checkout used to write
        # that checkout's build number into stable-latest, so stable clients
        # were never offered the newer APK.
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / 'pubspec.yaml').write_text(
                'name: app\nversion: 0.2.64+2557\n', encoding='utf-8')
            apk = root / 'app-release.apk'
            _fake_apk(apk)
            captured = {}

            def fake_publish(root_arg, staged, repository, token, channel='beta',
                             verify=True, version_build=None):
                captured['version_build'] = version_build
                return {'asset': 'StreamSports-beta.apk', 'bytes': 0,
                        'sha256': '', 'release': 'release'}

            with mock.patch.object(promote_stable, 'publish_mirror', fake_publish):
                promote_stable.promote(root, 'o/n', 'token', 'v0.2.74-2567',
                                       local_file=apk, verify=False)

        self.assertEqual(captured['version_build'], ('0.2.74', 2567))

    def test_bad_tag_is_rejected_before_any_network(self):
        from promote_stable import promote
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                promote(root, 'o/n', 'token', 'not-a-tag')


if __name__ == '__main__':
    unittest.main()
