#!/usr/bin/env python3
"""Update vendored skills without writing through home-directory symlinks."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def git(*args):
    return subprocess.check_output(["git", *map(str, args)], text=True).strip()


def update(root):
    root = Path(root).resolve()
    manifest = root / "packages/skills.json"
    sources = json.loads(manifest.read_text())
    skills = root / "home/.agents/skills"
    failures = []
    for directory in sorted(skills.iterdir()):
        if directory.is_dir() and directory.name not in sources:
            print(f"Skipped {directory.name}: no source in packages/skills.json")

    # Stage downloads outside home/; never run upstream installers or scripts.
    with tempfile.TemporaryDirectory(prefix="dot-skills-") as temp:
        cache = {}
        for name, spec in sources.items():
            try:
                if Path(name).name != name or name in (".", ".."):
                    raise ValueError("invalid skill name")
                target = skills / name
                if not target.is_dir() or target.is_symlink():
                    raise ValueError("expected an installed, non-symlink skill directory")
                relative = target.relative_to(root)
                if git("-C", root, "status", "--porcelain", "--ignored=matching", "--", relative):
                    raise ValueError("uncommitted or ignored files; move, commit or stash them first")
                url = spec["sourceUrl"]
                if url not in cache:
                    checkout = Path(temp) / str(len(cache))
                    # Remember failed clones too, avoiding repeated network attempts.
                    cache[url] = None
                    subprocess.run(["git", "clone", "--quiet", "--depth", "1", "--", url,
                                    str(checkout)], check=True)
                    cache[url] = checkout
                checkout = cache[url]
                if checkout is None:
                    raise ValueError("source clone failed")
                upstream = (checkout / spec["skillPath"]).resolve()
                if not upstream.is_relative_to(checkout.resolve()) or upstream.name != "SKILL.md":
                    raise ValueError("skillPath must point to SKILL.md inside the source")
                if not upstream.is_file():
                    raise ValueError(f"upstream skill missing: {spec['skillPath']}")
                source = upstream.parent
                # Do not vendor links that could escape the skill or git internals.
                if any(p.is_symlink() or p.name == ".git" for p in source.rglob("*")):
                    raise ValueError("upstream contains symlinks or nested git metadata")
                revision = git("-C", checkout, "rev-parse", "HEAD")
                # Stage beside the repository, not inside the Stow tree. This also
                # keeps renames on the same filesystem for rollback on copy errors.
                with tempfile.TemporaryDirectory(prefix=".dot-skills-", dir=root.parent) as stage:
                    staged = Path(stage) / "new"
                    backup = Path(stage) / "old"
                    shutil.copytree(source, staged, ignore=shutil.ignore_patterns(".git", "node_modules", "__pycache__"))
                    target.rename(backup)
                    try:
                        staged.rename(target)
                    except BaseException:
                        backup.rename(target)
                        raise
                spec["revision"] = revision
                print(f"Updated {name} ({revision[:12]})")
            except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
                failures.append(name)
                print(f"Failed {name}: {exc}", file=sys.stderr)
    # This is our source manifest, NOT the installer's user-managed lockfile.
    manifest.write_text(json.dumps(sources, indent=2, sort_keys=True) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(update(sys.argv[1]))
