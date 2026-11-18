import sys
import tempfile
import zipfile
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from promote_stable import versioned_asset_name


def _fake_apk(path):
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr('AndroidManifest.xml', '<manifest/>')
        archive.writestr('classes.dex', 'dex')


class PromoteStableTests(unittest.TestCase):
    def test_versioned_asset_name_matches_cut_release(self):
        self.assertEqual(versioned_asset_name('0.2.61', 2554),
                         'StreamSports-0.2.61-2554-beta.apk')

    def test_bad_tag_is_rejected_before_any_network(self):
        from promote_stable import promote
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            with self.assertRaises(ValueError):
                promote(root, 'o/n', 'token', 'not-a-tag')


if __name__ == '__main__':
    unittest.main()
