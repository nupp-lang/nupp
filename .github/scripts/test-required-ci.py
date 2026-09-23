"""Exercise job aggregation independently of GitHub's current run status."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "required_ci", Path(__file__).with_name("require-selected-jobs.py")
)
required_ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(required_ci)


class RequiredJobs(unittest.TestCase):
    jobs = {
        "integration": {"selectedBy": "linux-integration, macos-integration, windows-integration"},
    }

    def test_platform_alias_selects_aggregate_job(self):
        self.assertEqual(required_ci.selected_failures(
            {}, {"macos-integration": True}, self.jobs
        ), {"integration": "absent"})

    def test_unselected_failure_remains_failure(self):
        self.assertEqual(required_ci.selected_failures(
            {"integration": {"result": "failure"}}, {}, self.jobs
        ), {"integration": "failure"})


if __name__ == "__main__":
    unittest.main()
