import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("release_staging.sh").resolve()


class ReleaseStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.calls = root / "calls.jsonl"
        self.release = {
            "id": 123,
            "draft": True,
            "tag_name": "ci-staging-456-2",
            "name": "CI staging 456/2",
            "body": "CI staging only: example/repo run 456 attempt 2 commit " + "a" * 40,
            "target_commitish": "a" * 40,
            "author": {"login": "github-actions[bot]"},
        }
        self.env = {
            **os.environ,
            "PATH": str(root) + os.pathsep + os.environ["PATH"],
            "GITHUB_REPOSITORY": "example/repo",
            "GITHUB_RUN_ID": "456",
            "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_SHA": "a" * 40,
            "GITHUB_SERVER_URL": "https://github.com",
            "STAGING_RELEASE_ID": "123",
            "GITHUB_OUTPUT": str(root / "output"),
            "GITHUB_STEP_SUMMARY": str(root / "summary"),
            "MOCK_CALLS": str(self.calls),
            "MOCK_CREATE": "0",
            "MOCK_STATUS": "404",
            "MOCK_COLLISION": "0",
            "MOCK_DRAFT_COLLISION": "0",
            "MOCK_RESOLVED_ID": "123",
        }
        gh = root / "gh"
        gh.write_text("""#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ["MOCK_CALLS"], "a") as f:
    f.write(json.dumps(args) + "\\n")
if args[:3] == ["api", "--method", "POST"]:
    assert "draft=true" in args and "prerelease=false" in args
    assert "target_commitish=" + "a" * 40 in args
    print(123)
elif args[:3] == ["api", "--method", "DELETE"]:
    assert args[3] == "repos/example/repo/releases/123"
elif args[:2] == ["api", "--paginate"]:
    if os.environ["MOCK_DRAFT_COLLISION"] == "1":
        print(123)
elif args[:2] == ["release", "view"]:
    print(os.environ["MOCK_RESOLVED_ID"])
elif args[0] == "api" and "/git/ref/tags/" in args[1]:
    if os.environ["MOCK_COLLISION"] == "1":
        print("{}")
    else:
        print(json.dumps({"status": os.environ["MOCK_STATUS"]}))
        sys.exit(1)
elif args[0] == "api":
    calls = [json.loads(line) for line in open(os.environ["MOCK_CALLS"])]
    created = any(c[:3] == ["api", "--method", "POST"] for c in calls)
    if os.environ["MOCK_CREATE"] == "1" and not created:
        if os.environ["MOCK_COLLISION"] == "1":
            print("{}")
        else:
            print(json.dumps({"status": os.environ["MOCK_STATUS"]}))
            sys.exit(1)
    else:
        print(os.environ["MOCK_RELEASE"])
elif args[:2] not in (["release", "upload"], ["release", "download"]):
    sys.exit("Unexpected gh call: " + repr(args))
""")
        gh.chmod(0o755)

    def run_script(self, *args):
        self.env["MOCK_RELEASE"] = json.dumps(self.release)
        return subprocess.run(
            ["bash", str(SCRIPT), *args],
            env=self.env, text=True, capture_output=True,
        )

    def recorded(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_create_draft_with_explicit_commit_and_no_tag_write(self):
        self.env["MOCK_CREATE"] = "1"
        result = self.run_script("create")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(self.env["GITHUB_OUTPUT"]).read_text(), "release_id=123\n")
        self.assertEqual(len(self.recorded()), 6)

    def test_create_rejects_collision_and_non_404_failure(self):
        self.env["MOCK_CREATE"] = "1"
        for key, value in (("MOCK_COLLISION", "1"), ("MOCK_DRAFT_COLLISION", "1"), ("MOCK_STATUS", "403")):
            with self.subTest(key=key):
                self.env[key] = value
                result = self.run_script("create")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any("POST" in c for c in self.recorded()))
                self.env[key] = "404" if key == "MOCK_STATUS" else "0"

    def test_transports_validate_then_use_release_assets_without_overwrite(self):
        for args in (("upload", "bundle.tar.gz"), ("download", "bundle.tar.gz", "destination")):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.recorded()
                self.assertEqual(calls[-4], ["api", "repos/example/repo/releases/123"])
                self.assertEqual(calls[-3][:3], ["release", "view", "ci-staging-456-2"])
                self.assertEqual(calls[-2], ["api", "repos/example/repo/git/ref/tags/ci-staging-456-2"])
                self.assertEqual(calls[-1][:3], ["release", args[0], "ci-staging-456-2"])
                self.assertNotIn("--clobber", calls[-1])

    def test_rejects_published_or_foreign_release_before_any_access(self):
        cases = {
            "id": 124,
            "draft": False,
            "tag_name": "ci-staging-456-1",
            "name": "not staging",
            "body": "owned by another run",
            "target_commitish": "b" * 40,
            "author": {"login": "someone-else"},
        }
        for field, value in cases.items():
            original = self.release[field]
            for operation in (("upload", "bundle.tar.gz"), ("download", "*", "out"), ("delete",)):
                with self.subTest(field=field, operation=operation):
                    self.release[field] = value
                    self.calls.unlink(missing_ok=True)
                    result = self.run_script(*operation)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("not owned", result.stderr)
                    self.assertEqual(len(self.recorded()), 1)
            self.release[field] = original

    def test_delete_only_exact_validated_release_id(self):
        result = self.run_script("delete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded()[-1], ["api", "--method", "DELETE", "repos/example/repo/releases/123"])

    def test_rejects_cli_resolving_a_different_id(self):
        self.env["MOCK_RESOLVED_ID"] = "124"
        result = self.run_script("delete")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different release ID", result.stderr)
        self.assertFalse(any("DELETE" in c for c in self.recorded()))

    def test_rejects_staging_tag_appearing_before_access(self):
        self.env["MOCK_COLLISION"] = "1"
        for args in (("upload", "bundle.tar.gz"), ("download", "*", "out"), ("delete",)):
            with self.subTest(args=args):
                self.calls.unlink(missing_ok=True)
                result = self.run_script(*args)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("staging tag already exists", result.stderr)
                self.assertEqual(len(self.recorded()), 3)


if __name__ == "__main__":
    unittest.main()
