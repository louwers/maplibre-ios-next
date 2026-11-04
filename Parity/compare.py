"""Builds the parity report from the outputs of Parity/run.sh.

Compares classic MapLibre iOS with maplibre-ios-next:
  - API surface (out/api-diff.json from api/check-api.sh);
  - runtime API coverage (out/<impl>/coverage.json);
  - MapLibre iOS's own tests (out/<impl>/behaviour-tests.json, from xcresulttool);
  - trace tests (out/<impl>/traces/*.jsonl), value by value, with a float tolerance;
  - render tests (out/<impl>/render/), pixel by pixel.
Writes out/report.md, out/report.html, out/report.json and diff images under
out/render-diff/. Run with python3 -I; no dependencies.
"""

import argparse
import base64
import html
import json
import os
import re
import struct
import zlib

IMPLS = ("classic", "next")
REL_TOL = 1e-5
ABS_TOL = 1e-6
NUMBER = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
POINTER = re.compile(r"0x[0-9a-fA-F]{4,}")
UUID = re.compile(r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}")
IMPL_NAME = re.compile(r"org\.maplibre\.parity\.(?:classic|next)")


def normalize_text(text):
    """Removes what differs between processes: addresses, app container UUIDs, bundle IDs."""
    return IMPL_NAME.sub("org.maplibre.parity.IMPL", UUID.sub("UUID", POINTER.sub("0x?", text)))


def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


# MARK: - Values


def numbers_close(a, b):
    return a == b or abs(a - b) <= max(ABS_TOL, REL_TOL * max(abs(a), abs(b)))


def strings_close(a, b):
    """Equal strings, or strings that differ only in numbers within tolerance.
    Object addresses ("0x1234abcd") never count as differences."""
    if a == b:
        return True
    a, b = normalize_text(a), normalize_text(b)
    if a == b:
        return True
    if NUMBER.sub("#", a) != NUMBER.sub("#", b):
        return False
    na, nb = NUMBER.findall(a), NUMBER.findall(b)
    return len(na) == len(nb) and all(numbers_close(float(x), float(y)) for x, y in zip(na, nb))


def values_close(a, b):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return numbers_close(float(a), float(b))
    if isinstance(a, str) and isinstance(b, str):
        return strings_close(a, b)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(values_close(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(values_close(a[k], b[k]) for k in a)
    return a == b


def short(value, limit=300):
    text = json.dumps(value, sort_keys=True, ensure_ascii=False)
    return text if len(text) <= limit else text[: limit - 1] + "…"


# MARK: - Tests


def test_results(path):
    """{suite/test: (result, [messages])} from `xcresulttool get test-results tests`."""
    data = load_json(path, {}) or {}
    results = {}

    def walk(node, suite):
        kind = node.get("nodeType")
        if kind == "Test Suite":
            suite = node.get("name", suite)
        if kind == "Test Case":
            name = node.get("name", "").rstrip("()")
            messages = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
            results[f"{suite}/{name}"] = (node.get("result", "Unknown"), messages)
        for child in node.get("children", []):
            walk(child, suite)

    for node in data.get("testNodes", []):
        walk(node, "")
    return results


def upstream_suites(parity):
    folder = os.path.join(parity, "Tests", "Upstream")
    suites = set()
    for name in os.listdir(folder):
        stem, ext = os.path.splitext(name)
        if ext in (".m", ".mm", ".swift") and stem.endswith(("Tests", "Test")):
            suites.add(stem)
    return suites


# MARK: - Traces


def load_traces(folder):
    """{(suite, test, key, occurrence): value}"""
    traces = {}
    if not os.path.isdir(folder):
        return traces
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".jsonl"):
            continue
        counts = {}
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except ValueError:
                    continue
                base = (entry["suite"], entry["test"], entry["key"])
                counts[base] = counts.get(base, 0) + 1
                traces[base + (counts[base],)] = entry["value"]
    return traces


def compare_traces(out):
    classic = load_traces(os.path.join(out, "classic", "traces"))
    next_ = load_traces(os.path.join(out, "next", "traces"))
    # Values that differ between two runs of classic (run.sh --stability) are
    # timing-dependent; they are reported apart from parity differences.
    rerun = load_traces(os.path.join(out, "classic-rerun", "traces"))
    unstable = {k for k in classic if rerun and (k not in rerun or not values_close(classic[k], rerun[k]))}
    suites = {}
    differences = []
    for key in sorted(classic.keys() | next_.keys(), key=lambda k: tuple(map(str, k))):
        suite = suites.setdefault(key[0], {"same": 0, "different": 0, "only_classic": 0, "only_next": 0,
                                           "unstable": 0})
        if key in unstable:
            suite["unstable"] += 1
            continue
        if key not in next_:
            suite["only_classic"] += 1
            differences.append({"key": key, "kind": "only classic", "classic": classic[key], "next": None})
        elif key not in classic:
            suite["only_next"] += 1
            differences.append({"key": key, "kind": "only next", "classic": None, "next": next_[key]})
        elif values_close(classic[key], next_[key]):
            suite["same"] += 1
        else:
            suite["different"] += 1
            differences.append({"key": key, "kind": "different", "classic": classic[key], "next": next_[key]})
    return suites, differences, bool(classic), bool(next_)


# MARK: - PNG


def png_decode(path):
    """(width, height, rows of RGBA bytes) for 8-bit, non-interlaced PNGs."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, chunks, idat = 8, {}, b""
    while pos < len(data):
        length, kind = struct.unpack(">I4s", data[pos : pos + 8])
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IDAT":
            idat += body
        else:
            chunks.setdefault(kind, body)
        if kind == b"IEND":
            break
    width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", chunks[b"IHDR"])
    if depth not in (8, 16) or interlace != 0 or color not in (0, 2, 4, 6):
        raise ValueError(f"unsupported PNG (depth {depth}, color {color}, interlace {interlace})")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color]
    bpp = channels * depth // 8
    stride = width * bpp
    raw = zlib.decompress(idat)
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[i]
        line = bytearray(raw[i + 1 : i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if kind == 1:
                line[x] = (line[x] + a) & 0xFF
            elif kind == 2:
                line[x] = (line[x] + b) & 0xFF
            elif kind == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 0xFF
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
        prev = line
        if depth == 16:
            # Keep the high byte of each sample.
            line = line[0::2]
        if channels == 4:
            rows.append(bytes(line))
        else:
            rgba = bytearray()
            for x in range(width):
                px = line[x * channels : (x + 1) * channels]
                if channels == 1:
                    rgba += bytes((px[0], px[0], px[0], 255))
                elif channels == 2:
                    rgba += bytes((px[0], px[0], px[0], px[1]))
                else:
                    rgba += bytes((px[0], px[1], px[2], 255))
            rows.append(bytes(rgba))
    return width, height, rows


def png_encode(width, height, rows):
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + row for row in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def color_delta(r1, g1, b1, a1, r2, g2, b2, a2):
    """pixelmatch's YIQ colour difference of two pixels blended on white, 0..1."""

    def blend(c, a):
        return 255 + (c - 255) * a / 255

    r1, g1, b1 = blend(r1, a1), blend(g1, a1), blend(b1, a1)
    r2, g2, b2 = blend(r2, a2), blend(g2, a2), blend(b2, a2)
    y = (r1 - r2) * 0.29889531 + (g1 - g2) * 0.58662247 + (b1 - b2) * 0.11448223
    i = (r1 - r2) * 0.59597799 - (g1 - g2) * 0.27417610 - (b1 - b2) * 0.32180189
    q = (r1 - r2) * 0.21147017 - (g1 - g2) * 0.52261711 + (b1 - b2) * 0.31114694
    return (0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q) / 35215


def image_diff(path_a, path_b, diff_path, threshold=0.1):
    """Like pixelmatch with `threshold`: counts pixels whose colour differs more."""
    wa, ha, ra = png_decode(path_a)
    wb, hb, rb = png_decode(path_b)
    if (wa, ha) != (wb, hb):
        return {"size_mismatch": [[wa, ha], [wb, hb]], "ratio": 1.0}
    limit = threshold * threshold
    different = 0
    out_rows = []
    for row_a, row_b in zip(ra, rb):
        out = bytearray()
        for x in range(0, wa * 4, 4):
            pa, pb = row_a[x : x + 4], row_b[x : x + 4]
            if pa == pb:
                gray = int(255 + ((pa[0] * 0.3 + pa[1] * 0.59 + pa[2] * 0.11) - 255) * 0.1 * pa[3] / 255)
                out += bytes((gray, gray, gray, 255))
            elif color_delta(*pa, *pb) > limit:
                different += 1
                out += b"\xff\x00\x00\xff"
            else:
                out += b"\xff\xd0\x00\xff"
        out_rows.append(bytes(out))
    os.makedirs(os.path.dirname(diff_path), exist_ok=True)
    with open(diff_path, "wb") as f:
        f.write(png_encode(wa, ha, out_rows))
    return {"different_pixels": different, "ratio": different / float(wa * ha), "size": [wa, ha]}


def compare_render(out, kind):
    results = {impl: load_json(os.path.join(out, impl, "render", "results.json"), {}) or {} for impl in IMPLS}
    rows = []
    for test in sorted(set(results["classic"]) | set(results["next"])):
        rc, rn = results["classic"].get(test, {}), results["next"].get(test, {})
        if kind == "onscreen":
            rc, rn = rc.get("onscreen") or {}, rn.get("onscreen") or {}
            if not rc and not rn:
                continue
        row = {"test": test, "classic": rc.get("status", "missing"), "next": rn.get("status", "missing"),
               "reason": rc.get("reason") or rn.get("reason")}
        a = os.path.join(out, "classic", "render", kind, test + ".png")
        b = os.path.join(out, "next", "render", kind, test + ".png")
        if os.path.exists(a) and os.path.exists(b):
            try:
                row.update(image_diff(a, b, os.path.join(out, "render-diff", kind, test + ".png")))
            except (ValueError, zlib.error) as error:
                row["error"] = str(error)
        rows.append(row)
    return rows


# MARK: - Report


def build(out, parity):
    report = {"api": load_json(os.path.join(out, "api-diff.json")), "status": {}, "coverage": {}}
    for impl in IMPLS:
        report["status"][impl] = load_json(os.path.join(out, impl, "status.json"), {})
        coverage = load_json(os.path.join(out, impl, "coverage.json"))
        if coverage:
            report["coverage"][impl] = {"total": coverage["total"], "missing": coverage["missing"]}

    tests = {impl: test_results(os.path.join(out, impl, "behaviour-tests.json")) for impl in IMPLS}
    suites = upstream_suites(parity)
    upstream = []
    for name in sorted(set(tests["classic"]) | set(tests["next"])):
        if name.split("/")[0] not in suites:
            continue
        c = tests["classic"].get(name, ("not run", []))
        n = tests["next"].get(name, ("not run", []))
        upstream.append({"test": name, "classic": c[0], "next": n[0], "classic_messages": c[1][:3],
                         "next_messages": n[1][:3]})
    report["upstream"] = upstream
    report["other_tests"] = {
        impl: {name: result for name, (result, _) in tests[impl].items() if name.split("/")[0] not in suites}
        for impl in IMPLS
    }

    trace_suites, trace_differences, has_classic, has_next = compare_traces(out)
    report["traces"] = {"suites": trace_suites, "differences": trace_differences,
                        "classic_ran": has_classic, "next_ran": has_next}
    report["render"] = {"snapshot": compare_render(out, "snapshot"), "onscreen": compare_render(out, "onscreen")}
    return report


def markdown(report):
    lines = ["# Parity report: classic MapLibre iOS vs maplibre-ios-next", ""]
    lines += ["## Status", "", "| Part | " + " | ".join(IMPLS) + " |", "|---|---|---|"]
    parts = sorted({p for impl in IMPLS for p in report["status"].get(impl, {})})
    for part in parts:
        cells = []
        for impl in IMPLS:
            s = report["status"].get(impl, {}).get(part)
            cells.append(f"{s['state']}{(': ' + s['message']) if s and s.get('message') else ''}" if s else "–")
        lines.append(f"| {part} | " + " | ".join(cells) + " |")

    api = report.get("api")
    lines += ["", "## API surface", ""]
    if api:
        for key, label in (("headers", "Public headers"), ("objc_symbols", "Objective-C symbols (clang -extract-api)"),
                           ("swift", "Swift declarations (swift-api-digester)")):
            part = api.get(key) or {}
            if key == "swift" and not part.get("available"):
                lines.append(f"- {label}: not available")
                continue
            diff = len(part.get("only_classic", [])) + len(part.get("only_next", [])) + len(part.get("changed", []))
            lines.append(f"- {label}: {part.get('classic_count')} classic, {part.get('next_count')} next, "
                         f"**{diff} differences**")
            for item in (part.get("only_classic", []) + part.get("only_next", []))[:20]:
                lines.append(f"  - `{item}`")
            for item in part.get("changed", [])[:20]:
                lines.append(f"  - changed: `{item if isinstance(item, str) else item.get('path')}`")
    else:
        lines.append("Not run (`Parity/run.sh api`).")

    lines += ["", "## Runtime API coverage", ""]
    for impl in IMPLS:
        c = report["coverage"].get(impl)
        if c:
            lines.append(f"- {impl}: {c['total'] - len(c['missing'])} of {c['total']} present, "
                         f"{len(c['missing'])} missing")
        else:
            lines.append(f"- {impl}: not run")
    missing = report["coverage"].get("next", {}).get("missing", [])
    if missing:
        lines += ["", "<details><summary>Missing in next</summary>", ""]
        lines += [f"- `{m}`" for m in missing]
        lines += ["", "</details>"]

    lines += ["", "## MapLibre iOS's own tests", ""]
    up = report["upstream"]
    if up:
        def count(impl, result):
            return sum(1 for t in up if t[impl] == result)

        for impl in IMPLS:
            lines.append(f"- {impl}: {count(impl, 'Passed')} passed, {count(impl, 'Failed')} failed, "
                         f"{count(impl, 'Skipped')} skipped, {count(impl, 'Expected Failure')} expected failures, "
                         f"{count(impl, 'not run')} not run")
        ran = {impl: any(t[impl] != "not run" for t in up) for impl in IMPLS}
        diff = [t for t in up if t["classic"] != t["next"]] if all(ran.values()) else []
        if all(ran.values()):
            lines += ["", f"{len(diff)} tests with different outcomes:"]
        else:
            lines += ["", "Outcomes are compared once both implementations ran."]
        if diff:
            lines += ["", "| Test | classic | next |", "|---|---|---|"]
            for t in diff:
                lines.append(f"| `{t['test']}` | {t['classic']} | {t['next']} |")
        failed_classic = [t for t in up if t["classic"] == "Failed"]
        if failed_classic:
            lines += ["", "Tests that fail against classic too (see Parity/README.md):", ""]
            for t in failed_classic:
                lines.append(f"- `{t['test']}`: {short(t['classic_messages'][:1], 160)}")
    else:
        lines.append("Not run.")

    lines += ["", "## Traces", ""]
    tr = report["traces"]
    if tr["suites"] and not (tr["classic_ran"] and tr["next_ran"]):
        impl = "classic" if tr["classic_ran"] else "next"
        lines += [f"Only {impl} ran; values recorded per suite:", "", "| Suite | values |", "|---|---|"]
        for suite, c in sorted(tr["suites"].items()):
            lines.append(f"| {suite} | {c['only_classic'] + c['only_next']} |")
    elif tr["suites"]:
        lines += ["| Suite | same | different | only classic | only next | unstable in classic |",
                  "|---|---|---|---|---|---|"]
        for suite, c in sorted(tr["suites"].items()):
            lines.append(f"| {suite} | {c['same']} | {c['different']} | {c['only_classic']} | {c['only_next']} "
                         f"| {c['unstable']} |")
        if tr["differences"]:
            lines += ["", "<details><summary>Differences</summary>", ""]
            for d in tr["differences"][:3000]:
                suite, test, key, occurrence = d["key"]
                lines.append(f"- `{suite}.{test}` `{key}`#{occurrence} ({d['kind']}): classic `{short(d['classic'])}` "
                             f"next `{short(d['next'])}`")
            lines += ["", "</details>"]
    else:
        lines.append("Not run.")

    for kind, title in (("snapshot", "Render tests through MLNMapSnapshotter"),
                        ("onscreen", "Render tests through an on-screen MLNMapView")):
        rows = report["render"][kind]
        lines += ["", f"## {title}", ""]
        if not rows:
            lines.append("Not run.")
            continue
        compared = [r for r in rows if "ratio" in r]
        identical = [r for r in compared if r["ratio"] == 0]
        close = [r for r in compared if 0 < r["ratio"] <= 0.01]
        statuses = {}
        for r in rows:
            key = f"classic {r['classic']} / next {r['next']}"
            statuses[key] = statuses.get(key, 0) + 1
        lines.append(f"{len(rows)} tests; {len(compared)} rendered by both: {len(identical)} identical, "
                     f"{len(close)} within 1 %, {len(compared) - len(identical) - len(close)} differ more.")
        lines.append("")
        lines += [f"- {k}: {v}" for k, v in sorted(statuses.items())]
        shown = [r for r in rows if not (r.get("ratio") == 0 and r["classic"] == r["next"]) and r["classic"] != "skipped"]
        if shown:
            lines += ["", "| Test | classic | next | different pixels |", "|---|---|---|---|"]
            for r in shown:
                ratio = f"{r['ratio'] * 100:.2f} %" if "ratio" in r else r.get("error", "–")
                if r.get("size_mismatch"):
                    ratio = f"size {r['size_mismatch'][0]} vs {r['size_mismatch'][1]}"
                lines.append(f"| `{r['test']}` | {r['classic']} | {r['next']} | {ratio} |")
    return "\n".join(lines) + "\n"


def data_uri(path):
    try:
        with open(path, "rb") as f:
            return "data:image/png;base64," + base64.b64encode(f.read()).decode()
    except OSError:
        return ""


def html_report(report, md, out):
    body = []
    for line in md.splitlines():
        if line.startswith("# "):
            body.append(f"<h1>{html.escape(line[2:])}</h1>")
        elif line.startswith("## "):
            body.append(f"<h2>{html.escape(line[3:])}</h2>")
        elif line.startswith("<details") or line.startswith("</details"):
            body.append(line)
        elif line.startswith("|"):
            if set(line) <= set("|-"):
                continue
            cells = [c.strip() for c in line.strip("|").split("|")]
            body.append("<tr>" + "".join(f"<td>{html.escape(c)}</td>" for c in cells) + "</tr>")
        elif line.strip():
            body.append(f"<p>{html.escape(line)}</p>")
    text = "\n".join(body)
    text = re.sub(r"((?:<tr>.*</tr>\n?)+)", r"<table>\1</table>", text)
    gallery = []
    for kind in ("snapshot", "onscreen"):
        rows = [r for r in report["render"][kind] if r.get("ratio", 0) > 0][:80]
        for r in rows:
            images = "".join(
                f"<figure><img alt='{label}' src='{data_uri(os.path.join(out, impl, 'render', kind, r['test'] + '.png'))}'>"
                f"<figcaption>{label}</figcaption></figure>"
                for impl, label in (("classic", "classic"), ("next", "next")))
            images += (f"<figure><img alt='diff' src='{data_uri(os.path.join(out, 'render-diff', kind, r['test'] + '.png'))}'>"
                       f"<figcaption>difference</figcaption></figure>")
            gallery.append(f"<div class='case'><h3>{html.escape(kind)}: {html.escape(r['test'])} "
                           f"({r['ratio'] * 100:.2f} %)</h3><div class='row'>{images}</div></div>")
    style = """
    :root { color-scheme: light dark; --fg: #1d1d1f; --bg: #fff; --line: #ddd; }
    @media (prefers-color-scheme: dark) { :root { --fg: #eee; --bg: #161616; --line: #333; } }
    body { font: 14px/1.45 -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg);
           max-width: 1100px; margin: 0 auto; padding: 16px; }
    table { border-collapse: collapse; margin: 8px 0; width: 100%; }
    td { border: 1px solid var(--line); padding: 3px 6px; vertical-align: top; word-break: break-word; }
    tr:first-child td { font-weight: 600; }
    .row { display: flex; gap: 8px; flex-wrap: wrap; }
    figure { margin: 0; } figure img { max-width: 256px; image-rendering: pixelated; border: 1px solid var(--line); }
    """
    return (f"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width'>"
            f"<title>Parity report</title><style>{style}</style></head><body>{text}"
            f"<h2>Render differences</h2>{''.join(gallery) or '<p>None.</p>'}</body></html>")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", required=True)
    p.add_argument("--parity", required=True)
    args = p.parse_args()
    report = build(args.out, args.parity)
    md = markdown(report)
    with open(os.path.join(args.out, "report.md"), "w", encoding="utf-8") as f:
        f.write(md)
    with open(os.path.join(args.out, "report.html"), "w", encoding="utf-8") as f:
        f.write(html_report(report, md, args.out))
    with open(os.path.join(args.out, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, default=list)
    print(f"wrote {os.path.join(args.out, 'report.md')} and report.html")


if __name__ == "__main__":
    main()
