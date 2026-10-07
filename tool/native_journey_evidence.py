"""Fail closed when Flutter's existing-app driver overlooks a test timeout."""
import re
import unittest

MARKER='NATIVE_JOURNEY_COMPLETE own_operations=6 author=2'


def require_native_journey(logs):
    if re.search(r'Some tests failed|Test timed out|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK',logs):
        raise RuntimeError('Native Flutter test failure/timeout in actual application logs')
    if MARKER not in logs:
        raise RuntimeError('Native journey completion evidence is missing')


class EvidenceGuardTests(unittest.TestCase):
    def test_complete_journey_is_accepted(self):
        require_native_journey(MARKER+'\nAll tests passed.')

    def test_framework_false_green_is_refused_even_with_a_marker(self):
        with self.assertRaises(RuntimeError):
            require_native_journey(MARKER+'\nSome tests failed.\nAll tests passed.')

    def test_missing_completion_is_refused(self):
        with self.assertRaises(RuntimeError):require_native_journey('All tests passed.')


def self_test():
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceGuardTests))
    if not result.wasSuccessful():raise RuntimeError('Native evidence guard self-tests failed')


if __name__=='__main__':self_test()
