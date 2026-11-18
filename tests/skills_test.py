"""Offline integration coverage: python3 -m unittest discover -s tests -p '*_test.py'."""
import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "skills", Path(__file__).resolve().parents[1] / "scripts/lib/skills.py")
skills = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(skills)


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "dotfiles"
        self.upstream = Path(self.temp.name) / "upstream"
        for directory in (self.root, self.upstream):
            directory.mkdir()
            git(directory, "init", "-q")
            git(directory, "config", "user.email", "test@example.com")
            git(directory, "config", "user.name", "Test")
        (self.upstream / "example").mkdir()
        (self.upstream / "example/SKILL.md").write_text("new upstream instructions\n")
        git(self.upstream, "add", ".")
        git(self.upstream, "commit", "-qm", "initial")
        self.target = self.root / "home/.agents/skills/example"
        self.target.mkdir(parents=True)
        (self.target / "SKILL.md").write_text("old instructions\n")
        (self.target / "obsolete.md").write_text("obsolete\n")
        self.lock = self.root / "home/.agents/.skill-lock.json"
        self.lock.write_text('{"user": "state"}\n')
        self.manifest = self.root / "packages/skills.json"
        self.manifest.parent.mkdir()
        self.write_sources({"example": {"sourceUrl": str(self.upstream),
                                        "skillPath": "example/SKILL.md"}})
        git(self.root, "add", ".")
        git(self.root, "commit", "-qm", "initial")

    def write_sources(self, sources):
        self.manifest.write_text(json.dumps(sources))

    def test_updates_and_records_revision_without_changing_lock_or_custom_skills(self):
        custom = self.target.parent / "custom"
        custom.mkdir()
        (custom / "SKILL.md").write_text("local")
        self.assertEqual(skills.update(self.root), 0)
        self.assertEqual((self.target / "SKILL.md").read_text(), "new upstream instructions\n")
        self.assertFalse((self.target / "obsolete.md").exists())
        self.assertEqual((custom / "SKILL.md").read_text(), "local")
        self.assertEqual(self.lock.read_text(), '{"user": "state"}\n')
        self.assertEqual(json.loads(self.manifest.read_text())["example"]["revision"],
                         git(self.upstream, "rev-parse", "HEAD"))

    def test_dirty_skill_is_not_overwritten(self):
        (self.target / "SKILL.md").write_text("local edit")
        self.assertEqual(skills.update(self.root), 1)
        self.assertEqual((self.target / "SKILL.md").read_text(), "local edit")

    def test_untracked_files_are_not_removed(self):
        (self.target / "notes.txt").write_text("important")
        self.assertEqual(skills.update(self.root), 1)
        self.assertEqual((self.target / "notes.txt").read_text(), "important")

    def test_ignored_runtime_files_are_not_removed(self):
        (self.root / ".gitignore").write_text("notes.txt\n")
        (self.target / "notes.txt").write_text("runtime state")
        self.assertEqual(skills.update(self.root), 1)
        self.assertEqual((self.target / "notes.txt").read_text(), "runtime state")

    def test_failure_does_not_prevent_other_updates(self):
        sources = json.loads(self.manifest.read_text())
        sources["missing"] = {"sourceUrl": str(self.upstream), "skillPath": "missing/SKILL.md"}
        self.write_sources(sources)
        self.assertEqual(skills.update(self.root), 1)
        self.assertEqual((self.target / "SKILL.md").read_text(), "new upstream instructions\n")

    def test_missing_upstream_leaves_existing_skill(self):
        self.write_sources({"example": {"sourceUrl": str(self.upstream),
                                        "skillPath": "missing/SKILL.md"}})
        self.assertEqual(skills.update(self.root), 1)
        self.assertEqual((self.target / "SKILL.md").read_text(), "old instructions\n")

    def test_path_escape_is_rejected(self):
        self.write_sources({"example": {"sourceUrl": str(self.upstream),
                                        "skillPath": "../../SKILL.md"}})
        self.assertEqual(skills.update(self.root), 1)
        self.assertTrue((self.target / "obsolete.md").exists())

    def test_symlink_in_upstream_is_rejected(self):
        (self.upstream / "example/escape").symlink_to("/etc/passwd")
        git(self.upstream, "add", ".")
        git(self.upstream, "commit", "-qm", "symlink")
        self.assertEqual(skills.update(self.root), 1)
        self.assertFalse((self.target / "escape").exists())


if __name__ == "__main__":
    unittest.main()
