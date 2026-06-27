"""Git-backed version control for memory files, using subprocess git calls.

Replaces dulwich with standard git commands for armv7 compatibility
(avoids C extension compilation).
"""

from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from loguru import logger


@dataclass
class CommitInfo:
    sha: str  # Short SHA (8 chars)
    message: str
    timestamp: str  # Formatted datetime

    def format(self, diff: str = "") -> str:
        """Format this commit for display, optionally with a diff."""
        header = f"## {self.message.splitlines()[0]}\n`{self.sha}` — {self.timestamp}\n"
        if diff:
            return f"{header}\n```diff\n{diff}\n```"
        return f"{header}\n(no file changes)"


@dataclass
class LineAge:
    """Age of a single line based on git blame."""

    age_days: int  # days since last modification


class GitStore:
    """Git-backed version control for memory files.

    Uses the system ``git`` command (``pkg install git``) instead of the
    ``dulwich`` Python library to avoid C-extension compilation on armv7.
    """

    def __init__(self, workspace: Path, tracked_files: list[str]):
        self._workspace = workspace
        self._tracked_files = tracked_files

    # -- helpers ---------------------------------------------------------------

    def _git(self, *args: str) -> subprocess.CompletedProcess:
        """Run a git command in the workspace."""
        return subprocess.run(
            ["git"] + list(args),
            cwd=str(self._workspace),
            capture_output=True,
            text=True,
        )

    def _git_ok(self, *args: str) -> bool:
        """Run a git command, return True on success."""
        return self._git(*args).returncode == 0

    def _git_out(self, *args: str) -> str:
        """Run a git command, return stdout (stripped) or empty string."""
        r = self._git(*args)
        return r.stdout.strip() if r.returncode == 0 else ""

    # -- repo status -----------------------------------------------------------

    def is_initialized(self) -> bool:
        """Check if the git repo has been initialized."""
        return (self._workspace / ".git").is_dir()

    # -- init ------------------------------------------------------------------

    def init(self) -> bool:
        """Initialize a git repo if not already initialized.

        Creates .gitignore and makes an initial commit.
        Returns True if a new repo was created, False if already exists.
        """
        if self.is_initialized():
            return False

        if self._is_inside_git_repo():
            logger.warning(
                "Workspace {} is already inside a git repo; "
                "skipping nested repo initialization",
                self._workspace,
            )
            return False

        try:
            self._git("init")
            self._git("config", "user.email", "nanobot@dream")
            self._git("config", "user.name", "nanobot")

            # Write .gitignore (merge with existing if present)
            gitignore = self._workspace / ".gitignore"
            dream_entries = self._build_gitignore()
            if gitignore.exists():
                existing = gitignore.read_text(encoding="utf-8")
                existing_lines = set(existing.splitlines())
                new_lines = [
                    line
                    for line in dream_entries.splitlines()
                    if line not in existing_lines
                ]
                if new_lines:
                    merged = existing.rstrip("\n") + "\n" + "\n".join(new_lines) + "\n"
                    gitignore.write_text(merged, encoding="utf-8")
            else:
                gitignore.write_text(dream_entries, encoding="utf-8")

            # Ensure tracked files exist (touch them if missing) so the initial
            # commit has something to track.
            for rel in self._tracked_files:
                p = self._workspace / rel
                p.parent.mkdir(parents=True, exist_ok=True)
                if not p.exists():
                    p.write_text("", encoding="utf-8")

            # Initial commit
            self._git("add", ".gitignore", *self._tracked_files)
            self._git(
                "commit",
                "--allow-empty",
                "-m", "init: nanobot memory store",
            )
            logger.info("Git store initialized at {}", self._workspace)
            return True
        except Exception:
            logger.exception("Git store init failed for {}", self._workspace)
            return False

    # -- daily operations ------------------------------------------------------

    def auto_commit(self, message: str) -> str | None:
        """Stage tracked memory files and commit if there are changes.

        Returns the short commit SHA, or None if nothing to commit.
        """
        if not self.is_initialized():
            return None

        try:
            # Check for changes before committing
            status = self._git_out("status", "--porcelain", "--", *self._tracked_files)
            if not status:
                return None

            self._git("add", "--", *self._tracked_files)
            r = self._git("commit", "-m", message)
            if r.returncode != 0:
                return None

            sha = self._git_out("rev-parse", "--short=8", "HEAD")
            return sha or None
        except Exception:
            logger.exception("Git auto_commit failed")
            return None

    # -- sha resolution --------------------------------------------------------

    def _resolve_sha(self, short_sha: str) -> str | None:
        """Expand a short SHA to full SHA, or None if ambiguous/missing."""
        sha = self._git_out("rev-parse", "--verify", short_sha)
        return sha or None

    # -- log -------------------------------------------------------------------

    def log(self, max_entries: int = 20) -> list[CommitInfo]:
        """Return recent commits touching tracked files."""
        if not self.is_initialized():
            return []
        try:
            out = self._git_out(
                "log",
                f"--max-count={max_entries}",
                "--format=%h|||%s|||%ai",
                "--", *self._tracked_files,
            )
            if not out:
                return []

            commits: list[CommitInfo] = []
            for line in out.splitlines():
                parts = line.split("|||", 2)
                if len(parts) == 3:
                    sha, msg, ts = parts
                    commits.append(CommitInfo(sha=sha, message=msg, timestamp=ts))
            return commits
        except Exception:
            logger.exception("Git log failed")
            return []

    # -- blame / line ages -----------------------------------------------------

    def line_ages(self, file_path: str) -> list[LineAge]:
        """Compute the age of each line in a tracked file via git blame.

        Returns one LineAge per line, in order.
        Returns an empty list if the repo is not initialized, the file is
        empty, or annotation fails.
        """
        if not self.is_initialized():
            return []

        target = self._workspace / file_path
        if not target.exists() or target.stat().st_size == 0:
            return []

        try:
            # Use porcelain format for machine parsing
            blame = self._git_out("blame", "--porcelain", "--", file_path)
            if not blame:
                return []
            return _compute_line_ages_from_blame(blame)
        except Exception:
            logger.exception("Git line_ages failed for {}", file_path)
            return []

    # -- diff ------------------------------------------------------------------

    def diff_commits(self, sha1: str, sha2: str) -> str:
        """Show diff between two commits."""
        if not self.is_initialized():
            return ""
        try:
            return self._git_out("diff", sha1, sha2)
        except Exception:
            logger.exception("Git diff_commits failed")
            return ""

    # -- lookup -----------------------------------------------------------------

    def find_commit(self, short_sha: str, max_entries: int = 20) -> CommitInfo | None:
        """Find a commit by short SHA prefix match."""
        for c in self.log(max_entries=max_entries):
            if c.sha.startswith(short_sha):
                return c
        return None

    def show_commit_diff(
        self, short_sha: str, max_entries: int = 20
    ) -> tuple[CommitInfo, str] | None:
        """Find a commit and return it with its diff vs the parent."""
        commits = self.log(max_entries=max_entries)
        for i, c in enumerate(commits):
            if c.sha.startswith(short_sha):
                if i + 1 < len(commits):
                    diff = self.diff_commits(commits[i + 1].sha, c.sha)
                else:
                    diff = ""
                return c, diff
        return None

    # -- restore ---------------------------------------------------------------

    def revert(self, commit: str) -> str | None:
        """Revert (undo) the changes introduced by the given commit.

        Restores all tracked memory files to the state at the commit's parent,
        then creates a new commit recording the revert.

        Returns the new commit SHA, or None on failure.
        """
        if not self.is_initialized():
            return None
        try:
            full_sha = self._resolve_sha(commit)
            if not full_sha:
                logger.warning("Git revert: SHA not found: {}", commit)
                return None

            # Check it's not a root commit
            parent = self._git_out("rev-parse", f"{full_sha}^")
            if not parent:
                logger.warning("Git revert: cannot revert root commit {}", commit)
                return None

            # Restore tracked files from parent commit
            for filepath in self._tracked_files:
                content = self._git_out("show", f"{parent}:{filepath}")
                if content is not None and self._git(
                    "show", f"{parent}:{filepath}"
                ).returncode == 0:
                    dest = self._workspace / filepath
                    dest.write_text(content, encoding="utf-8")

            # Commit the restored state
            msg = f"revert: undo {commit}"
            return self.auto_commit(msg)
        except Exception:
            logger.exception("Git revert failed for {}", commit)
            return None

    # -- internal helpers ------------------------------------------------------

    def _is_inside_git_repo(self) -> bool:
        """Walk up from self._workspace to the filesystem root, returning True
        if any ancestor directory contains a .git directory (or gitlink file).
        """
        try:
            r = self._git("rev-parse", "--is-inside-work-tree")
            return r.returncode == 0 and r.stdout.strip() == "true"
        except Exception:
            return False

    def _build_gitignore(self) -> str:
        """Generate .gitignore content from tracked files."""
        lines: list[str] = []
        for f in self._tracked_files:
            lines.append(f"/{f}")
        return "*\n" + "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Blame-parsing helpers (pure Python, replaces dulwich.annotate)
# ---------------------------------------------------------------------------


def _compute_line_ages_from_blame(blame_output: str) -> list[LineAge]:
    """Parse ``git blame --porcelain`` output and return per-line ages."""
    now = datetime.now(tz=timezone.utc).date()

    # Track commit-timestamp mapping (porcelain format)
    commit_times: dict[str, datetime] = {}
    ages: list[LineAge] = []
    lines = blame_output.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        # Header line starts with SHA and filename
        parts = line.split()
        if len(parts) < 4 or not _is_sha(parts[0]):
            i += 1
            continue
        sha = parts[0]

        # Read metadata lines until the actual content line
        i += 1
        while i < len(lines) and lines[i].startswith("\t"):
            # Content line, end of this entry
            ct = commit_times.get(sha)
            if ct:
                age = (now - ct.date()).days
                ages.append(LineAge(age_days=age))
            else:
                ages.append(LineAge(age_days=0))
            i += 1
            break
        while i < len(lines):
            line = lines[i]
            if line.startswith("author-time "):
                ts = int(line.split()[1])
                commit_times[sha] = datetime.fromtimestamp(ts, tz=timezone.utc)
            elif line.startswith("\t"):
                ct = commit_times.get(sha)
                if ct:
                    age = (now - ct.date()).days
                    ages.append(LineAge(age_days=age))
                else:
                    ages.append(LineAge(age_days=0))
                i += 1
                break
            elif line == "":
                i += 1
                break
            i += 1
        else:
            break

    return ages


def _is_sha(s: str) -> bool:
    """Check if a string looks like a git SHA (40 hex chars)."""
    return len(s) == 40 and all(c in "0123456789abcdef" for c in s)
