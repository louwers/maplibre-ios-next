// The style object model: layers, sources, images, light, transitions.

#import "ParityMapTestCase.h"

@interface MLNStyleTraceTests : ParityMapTestCase
@end

@implementation MLNStyleTraceTests

- (void)recordLayers:(NSString *)key {
  [self.recorder record:key value:self.mapView.style.layers];
}

- (void)testStyleModel {
  MLNStyle *style = self.mapView.style;
  [self.recorder record:@"name" value:style.name];
  [self recordLayers:@"layers"];
  [self.recorder record:@"sources" value:style.sources];
  [self.recorder record:@"transition" value:[NSValue valueWithMLNTransition:style.transition]];
  [self.recorder record:@"performsPlacementTransitions" value:@(style.performsPlacementTransitions)];
  [self.recorder record:@"layerByIdentifier" value:[style layerWithIdentifier:@"road"]];
  [self.recorder record:@"missingLayer" value:[style layerWithIdentifier:@"missing"]];
  [self.recorder record:@"sourceByIdentifier" value:[style sourceWithIdentifier:@"points"]];
  [self.recorder record:@"layerIdentity" value:@([style layerWithIdentifier:@"road"] == [style layerWithIdentifier:@"road"])];
  [self.recorder record:@"sourceIdentity" value:@([style sourceWithIdentifier:@"points"] == [style sourceWithIdentifier:@"points"])];
}

- (void)testExistingLayerProperties {
  MLNStyle *style = self.mapView.style;
  MLNLineStyleLayer *road = (MLNLineStyleLayer *)[style layerWithIdentifier:@"road"];
  [self.recorder record:@"road.lineColor" value:road.lineColor];
  [self.recorder record:@"road.lineWidth" value:road.lineWidth];
  [self.recorder record:@"road.lineJoin" value:road.lineJoin];
  [self.recorder record:@"road.lineOpacity" value:road.lineOpacity];
  [self.recorder record:@"road.predicate" value:road.predicate];
  [self.recorder record:@"road.sourceIdentifier" value:road.sourceIdentifier];
  [self.recorder record:@"road.visible" value:@(road.visible)];
  [self.recorder record:@"road.zoom" value:@[ @(road.minimumZoomLevel), @(road.maximumZoomLevel) ]];
  MLNCircleStyleLayer *cities = (MLNCircleStyleLayer *)[style layerWithIdentifier:@"cities"];
  [self.recorder record:@"cities.circleColor" value:cities.circleColor];
  [self.recorder record:@"cities.circleRadius" value:cities.circleRadius];
  MLNBackgroundStyleLayer *background = (MLNBackgroundStyleLayer *)[style layerWithIdentifier:@"background"];
  [self.recorder record:@"background.backgroundColor" value:background.backgroundColor];
}

- (void)testAddingAndRemoving {
  MLNStyle *style = self.mapView.style;
  MLNShapeSource *source = [[MLNShapeSource alloc] initWithIdentifier:@"added"
                                                                shape:[MLNPointFeature new]
                                                              options:nil];
  [style addSource:source];
  MLNSymbolStyleLayer *symbols = [[MLNSymbolStyleLayer alloc] initWithIdentifier:@"symbols" source:source];
  symbols.iconImageName = [NSExpression expressionForConstantValue:@"marker"];
  symbols.text = [NSExpression expressionWithFormat:@"name"];
  [style addLayer:symbols];
  [self recordLayers:@"afterAddLayer"];
  MLNFillStyleLayer *fill = [[MLNFillStyleLayer alloc] initWithIdentifier:@"fill" source:source];
  [style insertLayer:fill belowLayer:[style layerWithIdentifier:@"road"]];
  MLNFillStyleLayer *fill2 = [[MLNFillStyleLayer alloc] initWithIdentifier:@"fill2" source:source];
  [style insertLayer:fill2 aboveLayer:[style layerWithIdentifier:@"road"]];
  MLNFillStyleLayer *fill3 = [[MLNFillStyleLayer alloc] initWithIdentifier:@"fill3" source:source];
  [style insertLayer:fill3 atIndex:1];
  [self recordLayers:@"afterInserts"];
  [self.recorder record:@"addedIdentity" value:@([style layerWithIdentifier:@"symbols"] == symbols)];
  [self.recorder record:@"duplicateLayer" block:^id {
    MLNFillStyleLayer *duplicate = [[MLNFillStyleLayer alloc] initWithIdentifier:@"fill" source:source];
    [style addLayer:duplicate];
    return @"added";
  }];
  [self.recorder record:@"duplicateSource" block:^id {
    [style addSource:[[MLNShapeSource alloc] initWithIdentifier:@"added" shape:nil options:nil]];
    return @"added";
  }];
  [self.recorder record:@"addSameLayerTwice" block:^id {
    [style addLayer:symbols];
    return @"added";
  }];
  [style removeLayer:symbols];
  [self recordLayers:@"afterRemoveLayer"];
  [self.recorder record:@"removedLayerText" block:^id {
    return symbols.text;
  }];
  NSError *error;
  BOOL removed = [style removeSource:source error:&error];
  [self.recorder record:@"removeSourceInUse" value:@{@"removed" : @(removed), @"error" : error ?: [NSNull null]}];
  [style removeLayer:fill];
  [style removeLayer:fill2];
  [style removeLayer:fill3];
  removed = [style removeSource:source error:&error];
  [self.recorder record:@"removeSourceUnused" value:@(removed)];
  [self.recorder record:@"sourcesAfter" value:style.sources];
  [style addLayer:symbols];
  [self recordLayers:@"readdedLayer"];
  [self.recorder record:@"readdedLayerText" value:symbols.text];
}

- (void)testPendingLayers {
  MLNShapeSource *source = [[MLNShapeSource alloc] initWithIdentifier:@"pending" shape:nil options:nil];
  MLNLineStyleLayer *line = [[MLNLineStyleLayer alloc] initWithIdentifier:@"pendingLine" source:source];
  [self.recorder record:@"pending.lineWidth.default" value:line.lineWidth];
  line.lineWidth = [NSExpression expressionForConstantValue:@4];
  line.lineColor = [NSExpression expressionForConstantValue:UIColor.redColor];
  line.lineDashPattern = [NSExpression expressionForConstantValue:@[ @1, @2 ]];
  line.predicate = [NSPredicate predicateWithFormat:@"kind == 'road'"];
  line.sourceLayerIdentifier = @"roads";
  line.minimumZoomLevel = 2;
  line.visible = NO;
  [self.recorder record:@"pending.lineWidth" value:line.lineWidth];
  [self.recorder record:@"pending.lineColor" value:line.lineColor];
  [self.recorder record:@"pending.lineDashPattern" value:line.lineDashPattern];
  [self.recorder record:@"pending.predicate" value:line.predicate];
  [self.recorder record:@"pending.sourceLayerIdentifier" value:line.sourceLayerIdentifier];
  [self.recorder record:@"pending.sourceIdentifier" value:line.sourceIdentifier];
  [self.recorder record:@"pending.minimumZoomLevel" value:@(line.minimumZoomLevel)];
  [self.recorder record:@"pending.visible" value:@(line.visible)];
  [self.recorder record:@"pending.description" value:[line.description componentsSeparatedByString:@";"].lastObject];
  [self.recorder record:@"pending.invalidValue" block:^id {
    line.lineWidth = [NSExpression expressionWithFormat:@"mgl_interpolate:withCurveType:parameters:stops:($zoomLevel, 'linear', nil, %@)", @{}];
    return line.lineWidth;
  }];
  [self.mapView.style addSource:source];
  [self.mapView.style addLayer:line];
  [self.recorder record:@"added.lineWidth" value:line.lineWidth];
  [self.recorder record:@"added.lineColor" value:line.lineColor];
  [self.recorder record:@"added.predicate" value:line.predicate];
  [self.recorder record:@"added.visible" value:@(line.visible)];
}

- (void)testImagesLightTransitions {
  MLNStyle *style = self.mapView.style;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4, 3)];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
    [UIColor.orangeColor setFill];
    UIRectFill(CGRectMake(0, 0, 4, 3));
  }];
  [style setImage:image forName:@"orange"];
  UIImage *read = [style imageForName:@"orange"];
  [self.recorder record:@"image" value:read ? @{@"size" : [NSValue valueWithCGSize:read.size], @"scale" : @(read.scale)} : nil];
  [style removeImageForName:@"orange"];
  [self.recorder record:@"removedImage" value:[style imageForName:@"orange"]];
  [self.recorder record:@"missingImage" value:[style imageForName:@"missing"]];

  MLNLight *light = style.light;
  [self.recorder record:@"light.anchor" value:light.anchor];
  [self.recorder record:@"light.position" value:light.position];
  [self.recorder record:@"light.color" value:light.color];
  [self.recorder record:@"light.intensity" value:light.intensity];
  light.intensity = [NSExpression expressionForConstantValue:@0.25];
  light.anchor = [NSExpression expressionForConstantValue:@"viewport"];
  style.light = light;
  [self.recorder record:@"light.after.intensity" value:style.light.intensity];
  [self.recorder record:@"light.after.anchor" value:style.light.anchor];

  style.transition = MLNTransitionMake(0.5, 0.25);
  [self.recorder record:@"transition" value:[NSValue valueWithMLNTransition:style.transition]];
  style.performsPlacementTransitions = NO;
  [self.recorder record:@"performsPlacementTransitions" value:@(style.performsPlacementTransitions)];
}

- (void)testLocalization {
  MLNStyle *style = self.mapView.style;
  MLNShapeSource *source = (MLNShapeSource *)[style sourceWithIdentifier:@"points"];
  MLNSymbolStyleLayer *labels = [[MLNSymbolStyleLayer alloc] initWithIdentifier:@"labels" source:source];
  labels.text = [NSExpression expressionWithFormat:@"name"];
  [style addLayer:labels];
  [style localizeLabelsIntoLocale:[NSLocale localeWithLocaleIdentifier:@"fr"]];
  [self.recorder record:@"labels.text.fr" value:labels.text];
  [style localizeLabelsIntoLocale:nil];
  [self.recorder record:@"labels.text.preferred" value:labels.text];
}

- (void)testSourcesAndShapes {
  MLNStyle *style = self.mapView.style;
  MLNShapeSource *points = (MLNShapeSource *)[style sourceWithIdentifier:@"points"];
  [self.recorder record:@"points.class" value:NSStringFromClass([points class])];
  [self.recorder record:@"points.shape" value:points.shape];
  [self.recorder record:@"points.URL" value:points.URL];
  MLNPolylineFeature *line = [MLNPolylineFeature polylineWithCoordinates:(CLLocationCoordinate2D[]){{0, 0}, {1, 1}} count:2];
  line.identifier = @7;
  line.attributes = @{@"kind" : @"new"};
  points.shape = line;
  [self.recorder record:@"points.shapeAfterSet" value:points.shape];
  MLNVectorTileSource *vector = [[MLNVectorTileSource alloc] initWithIdentifier:@"vector"
                                                             tileURLTemplates:@[ @"file:///tiles/{z}/{x}/{y}.pbf" ]
                                                                      options:@{
                                                                        MLNTileSourceOptionMinimumZoomLevel : @1,
                                                                        MLNTileSourceOptionMaximumZoomLevel : @12,
                                                                        MLNTileSourceOptionAttributionHTMLString : @"<a href=\"https://example.com\">© Example</a>",
                                                                      }];
  [style addSource:vector];
  [self.recorder record:@"vector.configurationURL" value:vector.configurationURL];
  [self.recorder record:@"vector.attributionInfos" value:[vector.attributionInfos valueForKeyPath:@"title.string"]];
  MLNRasterTileSource *raster = [[MLNRasterTileSource alloc] initWithIdentifier:@"raster"
                                                              tileURLTemplates:@[ @"file:///raster/{z}/{x}/{y}.png" ]
                                                                       options:@{MLNTileSourceOptionTileSize : @256}];
  [style addSource:raster];
  MLNImageSource *imageSource = [[MLNImageSource alloc] initWithIdentifier:@"image"
                                                         coordinateQuad:MLNCoordinateQuadMake(CLLocationCoordinate2DMake(1, 0), CLLocationCoordinate2DMake(0, 0), CLLocationCoordinate2DMake(0, 1), CLLocationCoordinate2DMake(1, 1))
                                                                    URL:[NSURL URLWithString:@"file:///image.png"]];
  [style addSource:imageSource];
  [self.recorder record:@"image.URL" value:imageSource.URL];
  [self.recorder record:@"sources" value:style.sources];
  [self.recorder record:@"sourceClasses" value:[[style.sources valueForKey:@"class"] valueForKey:@"description"]];
}

@end
