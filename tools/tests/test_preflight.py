import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from preflight import (quote_files, steps, summary_line, tail, test_command)


class PreflightTests(unittest.TestCase):
    def test_steps_run_the_same_checks_in_a_stable_order(self):
        planned = steps(['test/a_test.dart'])
        self.assertEqual([name for name, _ in planned],
                         ['analyze', 'tests', 'source audit', 'tools tests'])
        commands = dict(planned)
        self.assertEqual(commands['analyze'], 'flutter analyze')
        self.assertEqual(commands['source audit'], 'python3 tools/audit_repository.py')
        self.assertEqual(commands['tools tests'],
                         'python3 -m unittest discover -s tools/tests')

    def test_tests_are_parallel_unless_serial_is_asked_for(self):
        self.assertEqual(test_command(['test/a_test.dart']), 'flutter test test/a_test.dart')
        self.assertEqual(test_command(['test/a_test.dart'], serial=True),
                         'flutter test --concurrency=1 test/a_test.dart')

    def test_several_test_files_stay_separate_arguments(self):
        command = test_command([Path('test/a_test.dart'), Path('test/b_test.dart')])
        self.assertEqual(command, 'flutter test test/a_test.dart test/b_test.dart')

    def test_no_tests_skips_the_flutter_step(self):
        planned = steps([])
        self.assertEqual([name for name, _ in planned], ['analyze', 'source audit', 'tools tests'])
        self.assertEqual(test_command([]), 'flutter test')

    def test_a_path_with_spaces_is_quoted(self):
        self.assertEqual(quote_files(['test/odd name_test.dart']),
                         "'test/odd name_test.dart'")

    def test_summary_line_names_the_result_and_the_time(self):
        line = summary_line('analyze', True, 181.4)
        self.assertTrue(line.startswith('analyze'))
        self.assertIn('ok', line)
        self.assertIn('181s', line)
        self.assertIn('FAILED', summary_line('tests', False, 9))

    def test_tail_keeps_only_the_last_lines(self):
        text = '\n'.join(f'line {n}' for n in range(100))
        kept = tail(text, lines=3)
        self.assertEqual(kept, 'line 97\nline 98\nline 99')


if __name__ == '__main__':
    unittest.main()
