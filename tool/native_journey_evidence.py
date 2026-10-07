"""Fail closed when Flutter's existing-app driver overlooks a test timeout."""
import re
import unittest

MARKER='NATIVE_JOURNEY_COMPLETE own_operations=6 author=2'
OWNER_MARKER='NATIVE_OWNER_SUPERVISION_COMPLETE original_author=2 decision_actor=1'
SYNC_MARKER='NATIVE_SHARED_SYNC_COMPLETE jean=6 paul=1 personal_session=closed'


def require_native_journey(logs):
    if re.search(r'Some tests failed|Test timed out|EXCEPTION CAUGHT BY FLUTTER TEST FRAMEWORK',logs):
        raise RuntimeError('Native Flutter test failure/timeout in actual application logs')
    if MARKER not in logs:
        raise RuntimeError('Native journey completion evidence is missing')
    if OWNER_MARKER not in logs:
        raise RuntimeError('Native owner supervision completion evidence is missing')
    if SYNC_MARKER not in logs:
        raise RuntimeError('Native shared sync completion evidence is missing')


class EvidenceGuardTests(unittest.TestCase):
    def test_complete_journey_is_accepted(self):
        require_native_journey(MARKER+'\n'+OWNER_MARKER+'\n'+SYNC_MARKER+'\nAll tests passed.')

    def test_framework_false_green_is_refused_even_with_a_marker(self):
        with self.assertRaises(RuntimeError):
            require_native_journey(MARKER+'\nSome tests failed.\nAll tests passed.')

    def test_missing_completion_is_refused(self):
        with self.assertRaises(RuntimeError):require_native_journey('All tests passed.')

    def test_missing_owner_supervision_is_refused(self):
        with self.assertRaises(RuntimeError):require_native_journey(MARKER+'\nAll tests passed.')

    def test_missing_shared_sync_is_refused(self):
        with self.assertRaises(RuntimeError):require_native_journey(MARKER+'\n'+OWNER_MARKER+'\nAll tests passed.')


def self_test():
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(EvidenceGuardTests))
    if not result.wasSuccessful():raise RuntimeError('Native evidence guard self-tests failed')


if __name__=='__main__':self_test()
