"""How much of Rise Haptic Pack is copied / adapted from the two study mods.
Usage: py overlap.py <our root> <orig dir>
A "meaningful" line: not blank, not a comment, >= 12 characters after whitespace is collapsed (drops end/else/}...).
copied  = the same line exists in an original (whitespace-insensitive)
adapted = the same line with every number masked exists in an original (pattern rows with retuned values...)
"""
import os
import re
import sys

our_root, orig_dir = sys.argv[1], sys.argv[2]


def norm(line):
    return re.sub(r"\s+", " ", line.strip())


def mask(line):
    return re.sub(r"\d+(\.\d+)?", "#", line)


def meaningful(line, comment):
    return len(line) >= 12 and not line.startswith(comment)


orig_exact, orig_masked = set(), set()
orig_meaningful = {}
for name in os.listdir(orig_dir):
    lines = [norm(l) for l in open(os.path.join(orig_dir, name), encoding="utf-8", errors="replace")]
    keep = [l for l in lines if meaningful(l, "--")]
    orig_meaningful[name] = keep
    orig_exact.update(keep)
    orig_masked.update(mask(l) for l in keep)

used_orig_lines = set()
rows, totals = [], [0, 0, 0]
for folder, _, files in os.walk(our_root):
    for name in sorted(files):
        if not (name.endswith(".lua") or name.endswith(".c")):
            continue
        path = os.path.join(folder, name)
        comment = "--" if name.endswith(".lua") else "//"
        lines = [norm(l) for l in open(path, encoding="utf-8")]
        keep = [l for l in lines if meaningful(l, comment) and not l.startswith("*") and not l.startswith("/*")]
        exact = [l for l in keep if l in orig_exact]
        masked = [l for l in keep if l not in orig_exact and mask(l) in orig_masked]
        used_orig_lines.update(exact)
        rows.append((os.path.relpath(path, our_root), len(keep), len(exact), len(masked)))
        totals[0] += len(keep)
        totals[1] += len(exact)
        totals[2] += len(masked)

print(f"{'file':58} {'lines':>6} {'copied':>7} {'adapted':>8} {'new':>6}")
for rel, n, e, m in rows:
    new = n - e - m
    print(f"{rel:58} {n:6} {e:7} {m:8} {new:6}   ({100 * new / max(n, 1):3.0f}% new)")
n, e, m = totals
print(f"{'TOTAL':58} {n:6} {e:7} {m:8} {n - e - m:6}   ({100 * (n - e - m) / n:.0f}% new, "
      f"{100 * e / n:.1f}% copied, {100 * m / n:.1f}% adapted)")
for name, keep in orig_meaningful.items():
    reused = sum(1 for l in set(keep) if l in used_orig_lines)
    print(f"original {name}: {len(set(keep))} distinct meaningful lines, {reused} of them reused verbatim "
          f"({100 * reused / max(len(set(keep)), 1):.1f}%)")
