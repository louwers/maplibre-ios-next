# Shapes, features, predicates and expressions

Classic MapLibre iOS converted shapes, features, filters and constant values
to and from core C++ types (`mln::GeoJSON`, `mln::GeoJSONFeature`,
`mln::Value`, `mln::style::Filter`) and parsed GeoJSON with
`mapbox::geojson`. The C API takes and returns GeoJSON and style-spec JSON as
text, so this package does these conversions in Objective-C
(`ffi/MLNGeoJSON.mm`, `MLNShape`/`MLNFeature` `geoJSONObject`,
`NSExpression mgl_constantJSONValue`, `NSPredicate mgl_filterJSONObject`).
Where the results can differ from classic:

- **`+[MLNShape shapeWithData:encoding:error:]` JSON syntax errors.** Classic
  parsed with rapidjson and reported `"<offset> - <rapidjson message>"` in
  `NSLocalizedFailureReasonErrorKey`. The C API has no GeoJSON parser, so this
  package parses with `NSJSONSerialization` and reports its message instead.
  GeoJSON structure errors ("Feature must have a geometry property", …) are
  ported from `mapbox::geojson` and match. NSJSONSerialization also differs
  from rapidjson on edge cases such as duplicate keys and very large numbers.
- **Non-numeric coordinates.** `mapbox::geojson` called rapidjson's
  `GetDouble()` on coordinate members without checking their type (an
  assertion in rapidjson). This package fails with "coordinates must be
  numbers". *Unverified* what classic release builds did.
- **Empty polygon rings.** Classic took `front()` of a polygon with no rings
  (undefined behavior). This package initializes the polygon without
  coordinates, which raises `NSInvalidArgumentException` ("A multipoint must
  have at least one vertex.").
- **`-[MLNShape geoJSONDataUsingEncoding:]` output bytes.** Classic wrote
  `mapbox::geojson::stringify()` (rapidjson: `1.0` for doubles, member order
  type/geometry/properties/id). This package writes `NSJSONSerialization` output
  of the same GeoJSON object (`1` for integral doubles, dictionary order). The
  JSON is equivalent; the bytes are not.
- **Feature equality (`-[MLNFeature isEqual:]`).** Classic compared
  `mln::GeoJSON` values, whose variants distinguish `true` from `1` and
  `1` (uint64) from `1.0` (double). This package compares the Foundation
  GeoJSON objects, and `NSNumber` equality does not make those distinctions
  (`@YES` equals `@1`, `@1` equals `@1.0`).
- **Colors as feature attributes or identifiers.** `mln::Color::stringify()`
  formatted components with rapidjson's Grisu2 double writer. This package
  writes the shortest `%g` representation that reads back as the same double,
  which is the same for all values in a color's range unless Grisu2 is
  suboptimal (rare). *Unverified* on real values.
- **Filter validation (`mgl_filter`).** Classic converted predicates to
  `mln::style::Filter` and raised "Invalid filter value: <core message>". The
  C API validates expressions with `mln_style_expression_create()` (expected
  type boolean), whose diagnostic lists each parse error with its location; the
  text after "Invalid filter value: " differs from classic's. Predicates
  always produce expression syntax, so legacy filter forms, which the core
  converted separately, do not arise.
- **Removed private conversions.** `-[NSExpression mgl_featureType]`,
  `mgl_aggregateFeatureType`, `mgl_aggregateFeatureIdentifier`,
  `-[NSComparisonPredicate mgl_constantValue/mgl_featureType/mgl_featureIdentifier]`
  and `-[NSCompoundPredicate mgl_subfilters]` built core filter types and had
  no callers left; they were dropped. No public API depended on them.
- **Offline region definitions.** Classic built `mln::OfflineRegionDefinition`
  with the geometry as `mln::Geometry<double>`. The C API takes the geometry of a
  shape region as GeoJSON text, which this package writes from the shape's
  geometry object; a region read back from the database is parsed from that
  text. Shapes survive the round trip as their geometry (feature identifiers
  and attributes are dropped, as in classic).
