"""Reads the Objective-C API of MapLibre's public headers from a clang AST dump.

check-api.sh dumps the AST of `#import "MapLibre.h"` with -fmodules and the
headers on the include path, so system frameworks stay modules (not dumped)
and only MapLibre's declarations are in the dump.
"""

import json
import os


class _FileTracker:
    """clang's JSON omits a location's file when it equals the previous one."""

    def __init__(self):
        self.file = None

    def visit_loc(self, loc):
        if not isinstance(loc, dict):
            return
        for sub in ("spellingLoc", "expansionLoc"):
            if sub in loc:
                self.visit_loc(loc[sub])
        if "file" in loc:
            self.file = loc["file"]

    def walk(self, node):
        if isinstance(node, dict):
            if "loc" in node:
                self.visit_loc(node["loc"])
            if "range" in node:
                self.visit_loc(node["range"].get("begin"))
                self.visit_loc(node["range"].get("end"))
            for child in node.get("inner", []):
                self.walk(child)


def _unavailable(node):
    for child in node.get("inner", []):
        kind = child.get("kind")
        if kind == "UnavailableAttr":
            return True
        if kind == "AvailabilityAttr" and child.get("unavailable"):
            return True
    return False


def _optional(node):
    return node.get("control") == "optional" or node.get("implementationControl") == "optional"


def _members(node):
    methods, properties = {}, {}
    for member in node.get("inner", []):
        kind = member.get("kind")
        if kind == "ObjCMethodDecl" and not member.get("isImplicit"):
            key = ("-" if member.get("instance") else "+") + member["name"]
            methods[key] = {"unavailable": _unavailable(member), "optional": _optional(member)}
        elif kind == "ObjCPropertyDecl":
            name = member["name"]
            getter = (member.get("getter") or {}).get("name") or name
            setter = None
            if not member.get("readonly"):
                setter = (member.get("setter") or {}).get("name") or ("set" + name[0].upper() + name[1:] + ":")
            properties[name] = {
                "class": bool(member.get("class")),
                "getter": getter,
                "setter": setter,
                "unavailable": _unavailable(member),
                "optional": _optional(member),
            }
    return methods, properties


def collect(path, headers_dir):
    """Returns the API declared in headers under headers_dir, keyed by kind."""
    with open(path, encoding="utf-8") as f:
        root = json.load(f)
    headers_dir = os.path.realpath(headers_dir)
    api = {"classes": {}, "categories": {}, "protocols": {}, "functions": {}, "variables": {}}
    tracker = _FileTracker()
    for node in root.get("inner", []):
        before = tracker.file
        tracker.visit_loc(node.get("loc", {}))
        file = tracker.file or before
        tracker.walk(node)
        if not file or not os.path.realpath(file).startswith(headers_dir + os.sep):
            continue
        kind, name = node.get("kind"), node.get("name")
        if kind in ("ObjCInterfaceDecl", "ObjCProtocolDecl", "ObjCCategoryDecl"):
            methods, properties = _members(node)
            if kind == "ObjCInterfaceDecl" and not methods and not properties and "super" not in node:
                api["classes"].setdefault(name, None)  # forward declaration
                continue
            entry = {
                "methods": methods,
                "properties": properties,
                "protocols": [p["name"] for p in node.get("protocols", [])],
                "unavailable": _unavailable(node),
            }
            if kind == "ObjCInterfaceDecl":
                entry["super"] = (node.get("super") or {}).get("name")
                api["classes"][name] = entry
            elif kind == "ObjCProtocolDecl":
                if methods or properties or node.get("protocols") or name not in api["protocols"]:
                    api["protocols"][name] = entry
            else:
                entry["class"] = (node.get("interface") or {}).get("name")
                api["categories"][f"{entry['class']}({name})"] = entry
        elif kind == "FunctionDecl":
            api["functions"][name] = {
                "inline": bool(node.get("inline")) or node.get("storageClass") == "static",
                "unavailable": _unavailable(node),
            }
        elif kind == "VarDecl" and node.get("storageClass") == "extern":
            api["variables"][name] = {"unavailable": _unavailable(node)}
    # Forward declarations of classes defined elsewhere in the product.
    api["classes"] = {k: v for k, v in api["classes"].items() if v is not None}
    return api
