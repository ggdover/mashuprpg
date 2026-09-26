#!/usr/bin/env python3
"""Classify Godot errors in a gtest run log by module ownership (used by tools/gtest.sh).

Usage: gtest_classify.py <log> <owners_file|-> <repo>
Prints a summary and exits with 3 if there are errors in files owned by the caller, else 0.
An error block is a line containing "SCRIPT ERROR" or "Parse Error" (or "ERROR:" that names a
res:// path) plus the following "at:" line that names the file.
"""
import fnmatch
import re
import sys

IGNORE = re.compile(r"leaked at exit|Pages in use exist at exit|ObjectDB instances leaked|resources still in use at exit")
PATH_RE = re.compile(r"res://([^\s:)]+)")


def load_globs(path):
    if path == "-":
        return []
    globs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                globs.append(line)
    return globs


def owned(rel, globs):
    for g in globs:
        if fnmatch.fnmatch(rel, g) or fnmatch.fnmatch(rel, g.replace("/**", "/*")) or rel.startswith(g.rstrip("*").rstrip("/") + "/") and g.endswith("/**"):
            return True
    return False


def main():
    log, owners, _repo = sys.argv[1], sys.argv[2], sys.argv[3]
    globs = load_globs(owners)
    lines = open(log, errors="replace").read().splitlines()
    mine, others, unknown = [], [], []
    i = 0
    while i < len(lines):
        line = lines[i]
        is_err = ("SCRIPT ERROR" in line or "Parse Error" in line or line.startswith("ERROR:")) and not IGNORE.search(line)
        if is_err:
            ctx = line
            path = None
            m = PATH_RE.search(line)
            if m:
                path = m.group(1)
            if i + 1 < len(lines) and "at:" in lines[i + 1]:
                ctx += " | " + lines[i + 1].strip()
                m2 = PATH_RE.search(lines[i + 1])
                if m2:
                    path = m2.group(1)
                i += 1
            if path is None:
                if line.startswith("ERROR:"):
                    unknown.append(ctx)
                else:
                    unknown.append(ctx)
            elif globs and owned(path, globs):
                mine.append(ctx)
            else:
                others.append(ctx)
        i += 1
    print("[gtest] ---- error summary ----")
    print("[gtest] errors in YOUR files: %d" % len(mine))
    for e in mine[:15]:
        print("[gtest]   MINE  " + e[:300])
    print("[gtest] errors in OTHER modules' files: %d (not yours: never edit them; rerun later or with isolation)" % len(others))
    for e in others[:5]:
        print("[gtest]   OTHER " + e[:300])
    if unknown:
        print("[gtest] errors without a file: %d" % len(unknown))
        for e in unknown[:8]:
            print("[gtest]   ?     " + e[:300])
    sys.exit(3 if mine else 0)


if __name__ == "__main__":
    main()
