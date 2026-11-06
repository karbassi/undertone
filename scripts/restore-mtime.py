#!/usr/bin/env python3
"""Set each tracked file's mtime to the time of the last commit on this branch that changed it.

A fresh checkout stamps every file with the current time, so a restored `.build` sees every source as changed and
recompiles everything. Commit times are the same on every checkout of the same history, so unchanged files match
what the cached build recorded. Following first parents only (with -m, so merge commits list their files) keeps the
stamps increasing: a file changed since the cached build always gets a newer mtime than the cache saw.

Needs the full history (`fetch-depth: 0`); with a shallow clone every file gets the tip commit's time.
"""
import os
import subprocess


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


tracked = set(git("ls-files").splitlines())
stamped = set()
stamp = None
for line in git("log", "--first-parent", "-m", "--format=%x00%ct", "--name-only", "--no-renames").splitlines():
    if line.startswith("\0"):
        stamp = int(line[1:])
    elif line in tracked and line not in stamped:
        os.utime(line, (stamp, stamp))
        stamped.add(line)
print(f"restore-mtime: stamped {len(stamped)} of {len(tracked)} tracked files")
