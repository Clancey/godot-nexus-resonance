"""Exercise staging safety without contacting GitHub or creating any release."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/release_staging.sh"
GUARD = ROOT / "ci/scripts/check_no_actions_artifacts.sh"
FAKE_GH = r"""#!/usr/bin/env python3
import json
import os
import sys
args = sys.argv[1:]
with open(os.environ["GH_CALL_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
if os.environ.get("API_FAIL") == "true":
    sys.exit(1)
tag = "ci-stage-" + os.environ["GITHUB_RUN_ID"] + "-" + os.environ["GITHUB_RUN_ATTEMPT"]
release = {
    "id": 123, "draft": True, "tag_name": tag, "name": tag,
    "target_commitish": os.environ["GITHUB_SHA"],
    "body": "CI staging: {} run {} attempt {} commit {}".format(
        os.environ["GITHUB_REPOSITORY"], os.environ["GITHUB_RUN_ID"],
        os.environ["GITHUB_RUN_ATTEMPT"], os.environ["GITHUB_SHA"]),
}
release.update(json.loads(os.environ.get("RELEASE_OVERRIDES", "{}")))
if args[:2] in (["release", "upload"], ["release", "download"]):
    if os.environ.get("DUPLICATE_ASSET") == "true":
        sys.exit(1)
elif args[:2] == ["release", "view"]:
    print(json.dumps({"databaseId": int(os.environ.get("TAG_RESOLVED_ID", "123")), "isDraft": True}))
elif "POST" in args:
    print(123)
elif "DELETE" in args:
    pass
elif any("/git/matching-refs/" in arg for arg in args):
    print(json.dumps([{"ref": "refs/tags/" + tag}] if os.environ.get("TAG_EXISTS") else []))
elif any("/releases?" in arg for arg in args):
    print(json.dumps([release] if os.environ.get("RELEASE_EXISTS") else []))
else:
    print(json.dumps(release))
"""


class StagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        gh = self.path / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        self.log = self.path / "calls"
        self.env = {
            **os.environ,
            "PATH": f"{self.path}{os.pathsep}{os.environ['PATH']}",
            "GH_CALL_LOG": str(self.log),
            "GITHUB_REPOSITORY": "example/repo",
            "GITHUB_RUN_ID": "456",
            "GITHUB_RUN_ATTEMPT": "2",
            "GITHUB_SHA": "a" * 40,
            "STAGING_RELEASE_ID": "123",
            "GITHUB_OUTPUT": str(self.path / "output"),
            "GITHUB_STEP_SUMMARY": str(self.path / "summary"),
        }

    def run_script(self, *args, **env):
        return subprocess.run(
            ["bash", str(SCRIPT), *args], env={**self.env, **env},
            text=True, capture_output=True, check=False,
        )

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def assert_no_mutation(self):
        for call in self.calls():
            self.assertNotIn("POST", call)
            self.assertNotIn("DELETE", call)
            self.assertNotEqual(call[:2], ["release", "upload"])

    def test_create_is_draft_at_exact_commit_without_git_tag(self):
        result = self.run_script("create")
        self.assertEqual(result.returncode, 0, result.stderr)
        post = next(call for call in self.calls() if "POST" in call)
        for value in ("draft=true", "tag_name=ci-stage-456-2", "target_commitish=" + "a" * 40):
            self.assertIn(value, post)
        self.assertEqual((self.path / "output").read_text(), "release_id=123\n")
        self.assertFalse(any("git/refs" in arg for call in self.calls() for arg in call))

    def test_create_rejects_existing_release_or_tag(self):
        for env in ({"RELEASE_EXISTS": "true"}, {"TAG_EXISTS": "true"}):
            with self.subTest(env=env):
                self.log.write_text("")
                self.assertNotEqual(self.run_script("create", **env).returncode, 0)
                self.assert_no_mutation()

    def test_identity_mismatches_refuse_every_operation(self):
        mismatches = [
            {"id": 124}, {"draft": False}, {"tag_name": "ci-stage-456-1"},
            {"name": "another release"}, {"body": "another owner"},
            {"target_commitish": "b" * 40},
        ]
        for mismatch in mismatches:
            for args in (("upload", "bin-linux.tar.gz"), ("download", "*.tar.gz", "out"), ("delete",)):
                with self.subTest(mismatch=mismatch, args=args):
                    self.log.write_text("")
                    result = self.run_script(*args, RELEASE_OVERRIDES=json.dumps(mismatch))
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("identity mismatch", result.stderr)
                    self.assert_no_mutation()
                    self.assertFalse(any(call[:2] == ["release", "download"] for call in self.calls()))

    def test_existing_tag_blocks_deletion(self):
        self.assertNotEqual(self.run_script("delete", TAG_EXISTS="true").returncode, 0)
        self.assert_no_mutation()

    def test_tag_lookup_must_resolve_verified_id(self):
        for args in (("upload", "bin-linux.tar.gz"), ("download", "*.tar.gz", "out"), ("delete",)):
            with self.subTest(args=args):
                self.log.write_text("")
                result = self.run_script(*args, TAG_RESOLVED_ID="124")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("different release", result.stderr)
                self.assert_no_mutation()

    def test_api_failure_fails_closed(self):
        self.assertNotEqual(self.run_script("delete", API_FAIL="true").returncode, 0)
        self.assert_no_mutation()

    def test_upload_and_download_validate_before_using_unique_tag(self):
        for args in (("upload", "bin-linux.tar.gz"), ("download", "bin-linux.tar.gz", "out")):
            with self.subTest(args=args):
                self.log.write_text("")
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 0, result.stderr)
                calls = self.calls()
                self.assertIn("repos/example/repo/releases/123", calls[0])
                self.assertIn("ci-stage-456-2", calls[-1])
                self.assertNotIn("--clobber", calls[-1])

    def test_duplicate_asset_failure_is_not_ignored(self):
        self.assertNotEqual(
            self.run_script("upload", "bin-linux.tar.gz", DUPLICATE_ASSET="true").returncode, 0
        )

    def test_delete_targets_only_verified_release_id(self):
        result = self.run_script("delete")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1], ["api", "--method", "DELETE", "repos/example/repo/releases/123"])

    def test_missing_id_fails_before_any_api_call(self):
        self.assertNotEqual(self.run_script("delete", STAGING_RELEASE_ID="").returncode, 0)
        self.assertFalse(self.log.exists())


class StorageGuardTests(unittest.TestCase):
    def test_guard_rejects_producers_and_consumers_but_allows_releases(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / ".github/workflows/check.yml"
            workflow.parent.mkdir(parents=True)
            noun = "artifact"
            forbidden = [
                "actions/upload-" + noun + "@v5",
                "actions/download-" + noun + "@v5",
                "actions/upload-pages-" + noun + "@v3",
                "@actions/" + noun,
                "/actions/" + noun + "s",
                "gh run " + "download",
            ]
            for text in [*forbidden, "gh release upload ci-stage-1-1 bin.tar.gz"]:
                with self.subTest(text=text):
                    workflow.write_text(text + "\n")
                    result = subprocess.run(["bash", str(GUARD), str(root)], capture_output=True)
                    self.assertEqual(result.returncode == 0, text not in forbidden)


if __name__ == "__main__":
    unittest.main()
