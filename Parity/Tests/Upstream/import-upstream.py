"""Copies MapLibre iOS's own tests into the parity test target.

The tests run unchanged against both implementations wherever they use only
the public API. Mechanical rewrites (the umbrella import, two internal macros)
apply to every file; test methods that use the C++ core or private headers are
removed, each with its reason. ADAPTATIONS.md lists every change.

    python3 -I Parity/Tests/Upstream/import-upstream.py

Reads .upstream/ (scripts/fetch-upstream.sh).
"""

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
UPSTREAM = os.path.join(REPO, ".upstream", "platform")

# Tokens that mark a test method as using the C++ core or private headers.
PRIVATE_TOKENS = [
    "mbgl", "mln::", "mgl_filter", "mgl_predicateWithFilter", "mgl_constantMBGLValue",
    "mgl_aggregateMBGLValue", "mgl_featureType", "mgl_featureIdentifier", "rawLayer", "rawSource",
    "mbglMap", "MLNLocationCoordinate2DIsValid", "mgl_frameworkBundle", "MLNGeoJSONOptionsFromDictionary",
    "MBGLCustomGeometrySourceOptionsFromDictionary", "MLNTileSetFromTileURLTemplates", "initWithMBGL",
    "MLNFeatureFromMBGLFeature", "MLNFeaturesFromMBGLFeatures", "mbglFeature", "std::", "MLNStyleValueTransformer",
    "attributionInfosWithHTMLString", "MLNLatLng", "mgl_titleCasedString",
    "mgl_expressionWithContext", "MLNValueEvaluator", "isMapboxStreets", "mapboxStreets",
    "preferredMapboxStreetsLanguage", " invalidate]", "MLNAssertConstantEqualsValue", "MLNAssertEqualValues",
]

# file -> settings
FILES = {
    "darwin/test/MLNClockDirectionFormatterTests.m": {},
    "darwin/test/MLNCompassDirectionFormatterTests.m": {},
    "darwin/test/MLNCoordinateFormatterTests.m": {},
    "darwin/test/MLNDistanceFormatterTests.m": {},
    "darwin/test/MLNComputedShapeSourceTests.m": {},
    "darwin/test/MLNSourceQueryTests.m": {},
    "darwin/test/MLNImageSourceTests.m": {},
    "darwin/test/MLNOfflineRegionTests.m": {},
    "darwin/test/MLNMapProjectionTests.m": {},
    "darwin/test/MLNMapCameraTests.m": {},
    "darwin/test/MLNMapSnapshotterTests.m": {},
    "darwin/test/MLNMapViewTests.m": {},
    "darwin/test/MLNStyleLayerTests.h": {},
    "darwin/test/MLNStyleLayerTests.m": {},
    "darwin/test/MLNTestAssertionHandler.h": {},
    "darwin/test/MLNTestAssertionHandler.m": {},
    "darwin/test/MLNTestUtility.h": {},
    "darwin/test/MLNGeometryTests.mm": {},
    "darwin/test/MLNCodingTests.mm": {},
    "darwin/test/MLNStyleTests.mm": {},
    "darwin/test/MLNPredicateTests.mm": {},
    "darwin/test/MLNExpressionTests.mm": {},
    "darwin/test/MLNShapeSourceTests.mm": {},
    "darwin/test/MLNFeatureTests.mm": {},
    "darwin/test/MLNOfflineStorageTests.mm": {},
    "darwin/test/MLNOfflinePackTests.mm": {},
    "darwin/test/MLNImageTests.mm": {},
    "darwin/test/MLNDocumentationExampleTests.swift": {},
    "darwin/test/MLNDocumentationGuideTests.swift": {},
    "darwin/test/MLNSDKTestHelpers.swift": {},
    "darwin/test/amsterdam.geojson": {"resource": True},
    "darwin/test/one-liner.json": {"resource": True},
    "ios/test/MLNMockGestureRecognizers.h": {},
    "ios/test/MLNMockGestureRecognizers.m": {},
    "ios/test/MLNMapViewScaleBarTests.m": {},
    "ios/test/MLNMapViewFrustumOffsetTests.m": {},
    "ios/test/MLNMapViewPitchTests.m": {},
    "ios/test/MLNAnnotationViewTests.m": {},
    "ios/test/MLNMapViewLayoutTests.m": {},
    "ios/test/MLNMapViewZoomTests.mm": {},
    "ios/test/MLNMapViewCompassViewTests.mm": {},
    "ios/test/MLNMapViewDirectionTests.mm": {},
    "ios/test/MLNFeatureStateTests.swift": {},
    "ios/test/MLNMapViewDelegateIntegrationTests.swift": {},
    "ios/test/MLNAnnotationViewIntegrationTests.swift": {},
}

# Helper methods replaced by public-API equivalents: file -> {method: (body, note)}.
REPLACED_METHODS = {
    "darwin/test/MLNPredicateTests.mm": {
        "testSymmetryWithPredicate": (
            """- (void)testSymmetryWithPredicate:(NSPredicate *)forwardPredicate
                    mustRoundTrip:(BOOL)mustRoundTrip {
  // Parity: round-trips through the public JSON form instead of mbgl::style::Filter.
  NSPredicate *forwardPredicateAfter =
      [NSPredicate predicateWithMLNJSONObject:forwardPredicate.mgl_jsonExpressionObject];
  if (mustRoundTrip) {
    // A collection of ints may turn into an aggregate of longs, for
    // example, so compare formats instead of the predicates themselves.
    XCTAssertEqualObjects(forwardPredicate.predicateFormat.stringByRemovingPointerAddresses,
                          forwardPredicateAfter.predicateFormat.stringByRemovingPointerAddresses);
  } else {
    XCTAssertEqualObjects(forwardPredicate, forwardPredicateAfter);
  }
}
""",
            "The helper `testSymmetryWithPredicate:mustRoundTrip:` round-trips through the public "
            "`mgl_jsonExpressionObject`/`predicateWithMLNJSONObject:` instead of `mgl_filter`.",
        ),
    },
    "darwin/test/MLNStyleTests.mm": {
        "stringWithContentsOfStyleHeader": (
            "", "Removed the helper `stringWithContentsOfStyleHeader`: it reads headers from the private "
                "`+[NSBundle mgl_frameworkBundle]`; nothing calls it.",
        ),
    },
}

# Test methods removed for reasons the token scan does not catch: file -> {method: reason}.
REMOVED_METHODS = {
    "darwin/test/MLNCodingTests.mm": {
        "testUserLocation": "sets readonly properties through MLNUserLocation_Private.h",
    },
    "darwin/test/MLNPredicateTests.mm": {
        "testComparisonPredicatesWithOptions": "expects a failure of the mgl_filter round trip (XCTExpectFailure), which the public JSON round trip does not reproduce",
    },
}

# Files left out entirely, with the reason.
SKIPPED = {
    "darwin/test/MLNAttributionInfoTests.m": "Tests the private HTML attribution parser (MLNAttributionInfo_Private.h).",
    "darwin/test/MLNNSStringAdditionsTests.m": "Tests a private NSString category.",
    "darwin/test/MLNNSDateAdditionsTests.mm": "Tests private std::chrono conversions.",
    "darwin/test/MLNHeatmapColorTests.mm": "Compares against mbgl::style::HeatmapLayer values.",
    "darwin/test/MLNTileSetTests.mm": "Tests the private conversion to mbgl::Tileset.",
    "darwin/test/MLNResourceTests.mm": "Tests mbgl::Resource construction.",
    "darwin/test/MLNOfflineStorageInvalidationTests.mm": "Drives mbgl::DatabaseFileSource directly.",
    "darwin/test/MLNRendererConfigurationTests.m": "Tests the private MLNRendererConfiguration class.",
    "darwin/test/MLNStyleLayerTests.mm.ejs": "Generated per-layer tests compare against mbgl layers; Parity/Tests/Trace/Generated covers every property instead.",
    "ios/test/MLNMapViewGestureRecognizerTests.mm": "Inspects mbgl::Map through MLNMapView_Private.h.",
    "ios/test/MLNNetworkConfigurationTests.m": "Tests MLNNetworkConfiguration_Private.h.",
    "ios/test/MLNNSOrthographyAdditionsTests.m": "Tests a private NSOrthography category.",
    "ios/test/MLNMapAccessibilityElementTests.m": "Tests the private MLNMapAccessibilityElement classes.",
    "ios/test/MLNMapViewContentInsetTests.m": "Upstream leaves it out of its test target (platform/ios/test/BUILD.bazel); it fails against classic too.",
}

# (pattern, replacement, note) applied to every source file.
REWRITES = [
    (r'#import <MapLibre\.h>', '@import MapLibre;', "`#import <MapLibre.h>` (Bazel include path) became `@import MapLibre;`."),
    (r'#import <mln/math/wrap\.hpp>\n', '#import "ParityShims.h"\n', "`mln::util::wrap` became `ParityWrap` from Tests/Support/ParityShims.h."),
    (r'([\w.\[\]]+)\.mgl_frameForIdentifyTransform', r'ParityFrameForIdentityTransform(\1)',
     "The private `-[UIView mgl_frameForIdentifyTransform]` became `ParityFrameForIdentityTransform()` from Tests/Support/ParityShims.h."),
    (r'mln::util::wrap\(', 'ParityWrap(', None),
    (r'\[NSBundle mgl_applicationBundleIdentifier\]', '[NSBundle mainBundle].bundleIdentifier',
     "The private `+[NSBundle mgl_applicationBundleIdentifier]` became `[NSBundle mainBundle].bundleIdentifier`, its implementation."),
    (r'\[MLNColor mgl_colorWithColor:\{([^}]*)\}\]', r'ParityColorWithPremultipliedComponents(\1)',
     "The private `+[MLNColor mgl_colorWithColor:]` became `ParityColorWithPremultipliedComponents()` from Tests/Support/ParityShims.h, a copy of it."),
    (r'XCTExpectFailure\(((?:@"[^"]*"\s*)+)\)', r'XCTExpectFailureWithOptions(\1, [XCTExpectedFailureOptions nonStrictOptions])',
     "`XCTExpectFailure` became non-strict: the expected failures depend on how MapLibre iOS was built (they do not occur with the released binary)."),
    (r'self\.mgl_wholeRange', 'NSMakeRange(0, self.length)',
     "The private `-[NSString mgl_wholeRange]` became `NSMakeRange(0, self.length)`."),
    (r'#import "MLNFoundation_Private\.h"\n', '#import "ParityShims.h"\n', "MLN_OBJC_DYNAMIC_CAST macros come from Tests/Support/ParityShims.h."),
    (r'#import "(?:\.\./)+(?:darwin|ios)/src/[^"]+"\n', '', None),
    (r'#import "(MLN\w+_Private|NS\w+\+MLN\w*Additions|UI\w+\+MLNAdditions|MLNValueEvaluator)\.h"\n', '', None),
    (r'#(?:import|include) <mln/[^>]+>\n', '', None),
]

METHOD_RE = re.compile(r'^[-+] \([^)]*\)\s*(\w+)[^{;]*\{', re.M)
SWIFT_METHOD_RE = re.compile(r'^\s*func (test\w+)\([^)]*\)[^{]*\{', re.M)


def method_spans(text, swift):
    regex = SWIFT_METHOD_RE if swift else METHOD_RE
    spans = []
    for match in regex.finditer(text):
        start = match.start()
        depth, i = 0, match.end() - 1
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        end = i + 1
        # Include the line break after the method.
        while end < len(text) and text[end] in " \t":
            end += 1
        if end < len(text) and text[end] == "\n":
            end += 1
        spans.append((match.group(1), start, end))
    return spans


PUBLIC_HEADERS = set(os.listdir(os.path.join(REPO, "Sources", "MapLibre", "include", "MapLibre")))


def adapt(path, text):
    notes = []
    def drop_public(match):
        return "" if match.group(1) in PUBLIC_HEADERS else match.group(0)
    text, count = re.subn(r'#import "(\w+(?:\+\w+)?\.h)"\n', drop_public, text)
    if count and re.search(r'@import MapLibre;|#import <MapLibre\.h>', text) is None and not path.endswith(".h"):
        pass
    for pattern, replacement, note in REWRITES:
        text, count = re.subn(pattern, replacement, text)
        if count and note:
            notes.append(note)
    if re.search(r'#import "(\w+(?:\+\w+)?\.h)"', text) is None and "@import MapLibre;" not in text \
            and not path.endswith(".swift") and "MLNStyleLayerTests.h" not in text:
        text = "@import MapLibre;\n" + text
    swift = path.endswith(".swift")
    removed = []
    replacements = REPLACED_METHODS.get(path, {})
    explicit = REMOVED_METHODS.get(path, {})
    for name, start, end in reversed(method_spans(text, swift)):
        if name in explicit:
            removed.append((name, None, explicit[name]))
            text = text[:start] + text[end:]
            continue
        if name in replacements:
            body, note = replacements[name]
            text = text[:start] + body + text[end:]
            notes.append(note)
            continue
        body = text[start:end]
        tokens = sorted({t for t in PRIVATE_TOKENS if t in body})
        if tokens and (name.startswith("test") or swift):
            removed.append((name, tokens, None))
            text = text[:start] + text[end:]
    if any(shim in text for shim in ("ParityWrap(", "ParityFrameForIdentityTransform(", "ParityColorWith")) and '#import "ParityShims.h"' not in text:
        if "@import MapLibre;" in text:
            text = text.replace("@import MapLibre;", '@import MapLibre;\n#import "ParityShims.h"', 1)
        else:
            text = text.replace("#import <XCTest/XCTest.h>", '#import <XCTest/XCTest.h>\n\n#import "ParityShims.h"', 1)
    return text, notes, list(reversed(removed))


def main():
    out_lines = [
        "# Adaptations of upstream tests",
        "",
        "Generated by `import-upstream.py` from MapLibre iOS's tests at ios-v7.0.0",
        "(`platform/darwin/test`, `platform/ios/test`). Every file here is a copy with",
        "only the changes below; tests that need the C++ core or private headers are",
        "removed, since they cannot run against another implementation.",
        "",
        "## Copied files",
        "",
    ]
    for rel, settings in FILES.items():
        source = os.path.join(UPSTREAM, rel)
        dest = os.path.join(HERE, os.path.basename(rel))
        with open(source, encoding="utf-8") as f:
            text = f.read()
        if settings.get("resource"):
            with open(dest, "w", encoding="utf-8") as f:
                f.write(text)
            out_lines.append(f"- `{rel}`: resource, unchanged.")
            continue
        text, notes, removed = adapt(rel, text)
        header = "// Copied from platform/" + rel + " at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.\n" \
                 "// See ADAPTATIONS.md before editing.\n\n"
        with open(dest, "w", encoding="utf-8") as f:
            f.write(header + text)
        if not notes and not removed:
            out_lines.append(f"- `{rel}`: unchanged.")
            continue
        out_lines.append(f"- `{rel}`:")
        for note in notes:
            out_lines.append(f"  - {note}")
        for name, tokens, reason in removed:
            if reason:
                out_lines.append(f"  - removed `{name}`: {reason}.")
            else:
                out_lines.append(f"  - removed `{name}`: uses {', '.join('`' + t + '`' for t in tokens)}.")
    out_lines += ["", "## Files left out", ""]
    for rel, reason in SKIPPED.items():
        out_lines.append(f"- `{rel}`: {reason}")
    out_lines.append("")
    with open(os.path.join(HERE, "ADAPTATIONS.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(out_lines))


if __name__ == "__main__":
    main()
