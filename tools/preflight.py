"""Run the release checks at the same time, then report what failed.

The gate is four independent checks: the analyzer, the focused Flutter tests,
the source privacy audit and the tools' own unit tests. Run one after another
they cost their sum; run together they cost the slowest of them and use the
cores the others leave idle. On the release machine that is about four minutes
per cut, so it is the cheapest part of the process to reclaim.

Usage, from the checkout root:

    python3 tools/preflight.py test/live_sports_channels_test.dart test/l10n_parity_test.dart
    python3 tools/preflight.py                  # analyze and the audits only
    python3 tools/preflight.py --serial test/... # one at a time, as the old gate ran

Each check's output is captured until it finishes, so a passing run prints one
line per check with its wall time, and a failing run prints that check's tail.
The exit status is non-zero when any check fails.

Keep the full suite out of this: the sharded CI matrix runs it, and a serial
local run is the only local form that does not flake (see docs/development.md).
Flutter commands share the SDK's startup lock, so a slow machine may not see
the whole saving; the per-check timings show what actually happened.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
import shlex
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TAIL_LINES = 60

ANALYZE = 'flutter analyze'
SOURCE_AUDIT = 'python3 tools/audit_repository.py'
TOOLS_TESTS = 'python3 -m unittest discover -s tools/tests'


def quote_files(paths):
    """Quote test paths for the shell so a path with spaces stays one argument.

    Paths go to the shell in POSIX form: bash is what runs them, and Flutter
    accepts forward slashes on every host.
    """
    return ' '.join(shlex.quote(Path(str(path)).as_posix()) for path in paths)


def test_command(tests, serial=False):
    """`flutter test` for the given files, serial only when asked."""
    parts = ['flutter', 'test']
    if serial:
        parts.append('--concurrency=1')
    files = quote_files(tests)
    if files:
        parts.append(files)
    return ' '.join(parts)


def steps(tests=(), serial=False, run_tests=True):
    """The checks to run, slowest first so the long one starts immediately."""
    planned = [('analyze', ANALYZE)]
    if run_tests:
        planned.append(('tests', test_command(tests, serial)))
    planned.append(('source audit', SOURCE_AUDIT))
    planned.append(('tools tests', TOOLS_TESTS))
    return planned


def summary_line(name, ok, seconds):
    """One aligned result line: `analyze       ok     181s`."""
    status = 'ok' if ok else 'FAILED'
    return f'{name:<13} {status:<6} {seconds:5.0f}s'


def shell(command):
    """Run a command through bash so `flutter`/`python3` resolve on every host."""
    executable = shutil.which('bash')
    if executable is None:
        return shlex.split(command, posix=os.name != 'nt')
    return [executable, '-c', command]


def run(check, cwd=ROOT):
    """Run one check, keeping its output for a failure report."""
    name, command = check
    started = time.monotonic()
    result = subprocess.run(shell(command), cwd=cwd, capture_output=True, text=True)
    return {'name': name, 'command': command, 'ok': result.returncode == 0,
            'seconds': time.monotonic() - started,
            'output': (result.stdout or '') + (result.stderr or '')}


def tail(text, lines=TAIL_LINES):
    kept = text.strip().splitlines()[-lines:]
    return '\n'.join(kept)


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('tests', nargs='*', type=Path,
                        help='test files for flutter test; omit to skip tests')
    parser.add_argument('--no-tests', action='store_true', help='skip the Flutter tests')
    parser.add_argument('--serial', action='store_true',
                        help='run flutter test with --concurrency=1')
    parser.add_argument('--jobs', type=int, default=0,
                        help='checks to run at once (default: all of them)')
    args = parser.parse_args(argv)

    planned = steps(args.tests, serial=args.serial, run_tests=not args.no_tests)
    jobs = args.jobs or len(planned)
    lock = threading.Lock()
    print(f'{len(planned)} checks, {jobs} at a time', flush=True)
    started = time.monotonic()
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        results = []
        # Report as they finish: the fast audits should not wait behind the
        # slowest check just to be printed.
        pending = [pool.submit(run, check) for check in planned]
        for finished in as_completed(pending):
            result = finished.result()
            results.append(result)
            with lock:
                print(summary_line(result['name'], result['ok'], result['seconds']),
                      flush=True)
    total = time.monotonic() - started
    serial = sum(result['seconds'] for result in results)

    failures = [result for result in results if not result['ok']]
    for result in failures:
        print(f"\n--- {result['name']} failed: {result['command']} ---")
        print(tail(result['output']))
    if failures:
        print(f'\n{len(failures)} check(s) failed in {total:.0f}s.')
        return 1
    print(f'\nAll checks passed in {total:.0f}s '
          f'({serial:.0f}s if run one after another).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
