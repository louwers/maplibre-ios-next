// Copied from platform/darwin/test/MLNDistanceFormatterTests.m at ios-v7.0.0 by Parity/Tests/Upstream/import-upstream.py.
// See ADAPTATIONS.md before editing.

@import MapLibre;
#import <XCTest/XCTest.h>

@interface MLNDistanceFormatterTests : XCTestCase

@end

@implementation MLNDistanceFormatterTests

- (void)testAbbreviatedMetricUnits {
    MLNDistanceFormatter *formatter = [[MLNDistanceFormatter alloc] init];
    formatter.numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_CA"];
    for (CLLocationDistance distance=0; distance <= 10000; distance+=5) {
        NSString *unit = [[formatter stringFromDistance:distance] componentsSeparatedByString:@" "][1];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF IN %@", @[@"mm", @"cm", @"m", @"km"]];
        XCTAssert([predicate evaluateWithObject:unit], @"Should only contain metric units");
    }
}

- (void)testAbbreviatedImperialUnits {
    MLNDistanceFormatter *formatter = [[MLNDistanceFormatter alloc] init];
    formatter.numberFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    for (CLLocationDistance distance=0; distance <= 10000; distance+=5) {
        NSString *unit = [[formatter stringFromDistance:distance] componentsSeparatedByString:@" "][1];
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"SELF IN %@", @[@"ft", @"mi"]];
        XCTAssert([predicate evaluateWithObject:unit], @"Should only contain imperial units");
    }
}

@end
