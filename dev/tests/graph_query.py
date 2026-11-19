"""Parse RiseHapticPack_motion_graph.txt and answer questions about the Long Sword attack graph.
Usage: py graph_query.py <dump file> <command> [args]
  into <prefix>        nodes whose transition states include a node starting with prefix
  out <prefix>         transition states of nodes starting with prefix
  children <prefix>    children of nodes starting with prefix
  list <prefix>        node names starting with prefix
"""
import sys
from collections import defaultdict

path, command = sys.argv[1], sys.argv[2]
arg = sys.argv[3] if len(sys.argv) > 3 else ""

nodes = {}  # index -> (name, children, states, start_states)
for line in open(path, encoding="utf-8"):
    if not line.startswith("["):
        continue
    parts = [p.strip() for p in line.rstrip("\n").split("  |  ")]
    head = parts[0]
    index = int(head[1:head.index("]")])
    name = head[head.index("]") + 2:]
    fields = {"children": [], "states": [], "start_states": []}
    for p in parts[1:]:
        key, _, value = p.partition(": ")
        fields[key] = [v.strip() for v in value.split(", ")] if value else []
    nodes[index] = (name, fields["children"], fields["states"], fields["start_states"])

by_name = defaultdict(list)
for index, (name, *_rest) in nodes.items():
    by_name[name].append(index)


def show(names):
    for n in sorted(set(names)):
        print("  ", n)


if command == "into":
    hits = []
    for index, (name, children, states, start) in nodes.items():
        for s in states:
            if s.startswith(arg):
                hits.append(f"{name}  ->  {s}")
    show(hits)
elif command == "out":
    for index, (name, children, states, start) in sorted(nodes.items()):
        if name.startswith(arg):
            print(f"[{index}] {name}")
            for s in states:
                print("      ->", s)
elif command == "children":
    for index, (name, children, states, start) in sorted(nodes.items()):
        if name.startswith(arg):
            print(f"[{index}] {name}: children={children} start={start}")
elif command == "list":
    show([n for n, *_ in nodes.values() if n.startswith(arg)])
