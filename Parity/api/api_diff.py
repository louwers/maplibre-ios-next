"""Compares the public API of the classic and next implementations.

Writes a JSON summary with header, Objective-C symbol graph and Swift API
differences. Run with python3 -I.
"""

import argparse
import filecmp
import json
import os


def header_diff(classic, next_):
    a = {f for f in os.listdir(classic) if f.endswith(".h")}
    b = {f for f in os.listdir(next_) if f.endswith(".h")}
    changed = sorted(f for f in a & b if not filecmp.cmp(os.path.join(classic, f), os.path.join(next_, f), shallow=False))
    return {
        "classic_count": len(a),
        "next_count": len(b),
        "only_classic": sorted(a - b),
        "only_next": sorted(b - a),
        "changed": changed,
    }


def _fragments(symbol):
    return "".join(f.get("spelling", "") for f in symbol.get("declarationFragments", []))


def _normalize(symbol):
    return {
        "kind": symbol["kind"]["identifier"],
        "path": "/".join(symbol.get("pathComponents", [])),
        "declaration": _fragments(symbol),
        "availability": symbol.get("availability"),
        "access": symbol.get("accessLevel"),
        "doc": "\n".join(line.get("text", "") for line in (symbol.get("docComment") or {}).get("lines", [])),
    }


def symbol_diff(classic_path, next_path):
    def load(path):
        with open(path, encoding="utf-8") as f:
            graph = json.load(f)
        symbols = {s["identifier"]["precise"]: _normalize(s) for s in graph["symbols"]}
        relationships = {(r["kind"], r["source"], r["target"]) for r in graph.get("relationships", [])}
        return symbols, relationships

    a, ar = load(classic_path)
    b, br = load(next_path)
    changed = []
    for usr in sorted(a.keys() & b.keys()):
        if a[usr] != b[usr]:
            fields = [k for k in a[usr] if a[usr][k] != b[usr][k]]
            changed.append({"usr": usr, "path": a[usr]["path"], "fields": fields,
                            "classic": {k: a[usr][k] for k in fields}, "next": {k: b[usr][k] for k in fields}})
    return {
        "classic_count": len(a),
        "next_count": len(b),
        "only_classic": sorted(a[u]["path"] + " (" + a[u]["kind"] + ")" for u in a.keys() - b.keys()),
        "only_next": sorted(b[u]["path"] + " (" + b[u]["kind"] + ")" for u in b.keys() - a.keys()),
        "changed": changed,
        "relationships_only_classic": sorted(map(list, ar - br)),
        "relationships_only_next": sorted(map(list, br - ar)),
    }


def swift_diff(classic_path, next_path, diagnose_path):
    result = {"available": os.path.exists(classic_path) and os.path.exists(next_path)}
    if not result["available"]:
        return result

    def flatten(node, prefix, out):
        name = node.get("printedName") or node.get("name") or ""
        key = prefix + "/" + node.get("kind", "") + ":" + name
        out[key] = {k: node[k] for k in ("declKind", "usr", "moduleName", "isOpen", "objc_name",
                                          "declAttributes", "genericSig", "isThrowing", "static")
                    if k in node}
        for child in node.get("children", []):
            flatten(child, key, out)

    def load(path):
        with open(path, encoding="utf-8") as f:
            root = json.load(f)
        out = {}
        flatten(root.get("ABIRoot", root), "", out)
        return out

    a, b = load(classic_path), load(next_path)
    result.update({
        "classic_count": len(a),
        "next_count": len(b),
        "only_classic": sorted(a.keys() - b.keys()),
        "only_next": sorted(b.keys() - a.keys()),
        "changed": sorted(k for k in a.keys() & b.keys() if a[k] != b[k]),
    })
    if os.path.exists(diagnose_path):
        with open(diagnose_path, encoding="utf-8") as f:
            lines = [l.rstrip() for l in f if l.strip() and not l.startswith("/*") and not l.startswith("*/")]
        result["diagnose"] = [l for l in lines if not l.startswith("/* ") ]
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--classic-headers", required=True)
    p.add_argument("--next-headers", required=True)
    p.add_argument("--classic-symbols", required=True)
    p.add_argument("--next-symbols", required=True)
    p.add_argument("--classic-swift", required=True)
    p.add_argument("--next-swift", required=True)
    p.add_argument("--swift-diagnose", required=True)
    p.add_argument("--out", required=True)
    args = p.parse_args()
    result = {
        "headers": header_diff(args.classic_headers, args.next_headers),
        "objc_symbols": symbol_diff(args.classic_symbols, args.next_symbols),
        "swift": swift_diff(args.classic_swift, args.next_swift, args.swift_diagnose),
    }
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    h, s, w = result["headers"], result["objc_symbols"], result["swift"]
    print(f"headers: {h['classic_count']} classic, {h['next_count']} next, "
          f"{len(h['only_classic'])} only classic, {len(h['only_next'])} only next, {len(h['changed'])} changed")
    print(f"objc symbols: {s['classic_count']} classic, {s['next_count']} next, "
          f"{len(s['only_classic'])} only classic, {len(s['only_next'])} only next, {len(s['changed'])} changed")
    if w.get("available"):
        print(f"swift decls: {w['classic_count']} classic, {w['next_count']} next, "
              f"{len(w['only_classic'])} only classic, {len(w['only_next'])} only next, {len(w['changed'])} changed")
    else:
        print("swift: dump missing")


if __name__ == "__main__":
    main()
