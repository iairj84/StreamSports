import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from cut_release import (asset_name, bump_pubspec, changelog_entry, insert_changelog_entry,
                         next_release_version, note_bullets, release_body, release_title,
                         tag_name, version_label)


class CutReleaseTests(unittest.TestCase):
    def test_next_release_version_bumps_patch_and_build(self):
        self.assertEqual(next_release_version('0.2.18', 2511), ('0.2.19', 2512))
        self.assertEqual(next_release_version('1.9.9', 7), ('1.9.10', 8))

    def test_unknown_version_shape_is_rejected(self):
        with self.assertRaises(ValueError):
            next_release_version('0.2', 2511)
        with self.assertRaises(ValueError):
            next_release_version('0.2.x', 2511)

    def test_bump_pubspec_rewrites_only_the_version_line(self):
        text = 'name: app\ndescription: keep me\nversion: 0.2.18+2511\nflutter:\n'
        self.assertEqual(
            bump_pubspec(text, '0.2.19', 2512),
            'name: app\ndescription: keep me\nversion: 0.2.19+2512\nflutter:\n')

    def test_bump_pubspec_keeps_crlf_endings(self):
        text = 'name: app\r\nversion: 0.2.18+2511\r\n'
        self.assertEqual(bump_pubspec(text, '0.2.19', 2512),
                         'name: app\r\nversion: 0.2.19+2512\r\n')

    def test_missing_version_line_is_rejected(self):
        with self.assertRaises(ValueError):
            bump_pubspec('name: app\n', '0.2.19', 2512)

    def test_tag_asset_and_title_follow_the_published_convention(self):
        self.assertEqual(tag_name('0.2.19', 2512), 'v0.2.19-2512')
        self.assertEqual(asset_name('0.2.19', 2512), 'StreamSports-0.2.19-2512-beta.apk')
        self.assertEqual(release_title('0.2.19'), 'StreamSports 0.2.19 beta')
        self.assertEqual(version_label('0.2.19', 2512), '0.2.19 (2512)')

    def test_note_bullets_strip_dashes_and_blank_lines(self):
        notes = note_bullets('- First change\n\n* Second change\nThird change\n')
        self.assertEqual(notes, ['First change', 'Second change', 'Third change'])

    def test_empty_notes_are_rejected(self):
        with self.assertRaises(ValueError):
            note_bullets('   \n\n')

    def test_changelog_entry_matches_the_file_format(self):
        entry = changelog_entry('0.2.19', '9 November 2026', ['One change', 'Another change'])
        self.assertEqual(entry, '## 0.2.19 — 9 November 2026\n\n- One change\n- Another change\n\n')

    def test_new_section_goes_directly_below_the_heading(self):
        text = '# Changelog\n\n## 0.2.18 — 8 November 2026\n\n- Old change\n'
        entry = changelog_entry('0.2.19', '9 November 2026', ['New change'])
        self.assertEqual(
            insert_changelog_entry(text, entry),
            '# Changelog\n\n## 0.2.19 — 9 November 2026\n\n- New change\n\n'
            '## 0.2.18 — 8 November 2026\n\n- Old change\n')

    def test_insert_keeps_crlf_files_intact(self):
        text = '# Changelog\r\n\r\n## 0.2.18 — 8 November 2026\r\n\r\n- Old\r\n'
        entry = changelog_entry('0.2.19', '9 November 2026', ['New'])
        result = insert_changelog_entry(text, entry)
        self.assertIn('\r\n- New\r\n\r\n## 0.2.18', result)
        self.assertNotIn('\n', result.replace('\r\n', ''))

    def test_changelog_without_heading_is_rejected(self):
        with self.assertRaises(ValueError):
            insert_changelog_entry('## 0.2.18\n', changelog_entry('0.2.19', 'x', ['y']))

    def test_release_body_names_the_build_checksum_and_stable_address(self):
        digest = 'b' * 64
        body = release_body('iairj84/StreamSports', '0.2.19', 2512,
                            ['First change'], 'StreamSports-0.2.19-2512-beta.apk',
                            54014889, digest)
        self.assertIn('StreamSports 0.2.19 beta, build 2512.', body)
        self.assertIn('- First change', body)
        self.assertIn('StreamSports-0.2.19-2512-beta.apk', body)
        self.assertIn(digest, body)
        self.assertIn('54014889 bytes', body)
        self.assertIn('https://github.com/iairj84/StreamSports/releases/latest/download/'
                      'StreamSports-beta.apk', body)


class ReleaseBranchTests(unittest.TestCase):
    def test_default_branch_comes_from_the_remote_head(self):
        from cut_release import branch_from_remote_head
        tab = chr(9)
        self.assertEqual(branch_from_remote_head('ref: refs/heads/main' + tab + 'HEAD'), 'main')
        self.assertEqual(branch_from_remote_head('ref: refs/heads/trunk' + tab + 'HEAD'), 'trunk')
        self.assertEqual(branch_from_remote_head(''), 'main')
        self.assertEqual(branch_from_remote_head('garbage'), 'main')

if __name__ == '__main__':
    unittest.main()
