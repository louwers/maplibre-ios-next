// Records observations from parity tests as JSON, so the outputs of the classic
// and next implementations can be compared afterwards (Parity/compare.py).
//
// Files go to $PARITY_OUT (set through TEST_RUNNER_PARITY_OUT by run.sh), or a
// temporary directory when the tests run from Xcode.

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>

NS_ASSUME_NONNULL_BEGIN

@interface ParityRecorder : NSObject

/// The directory the parity outputs go to.
+ (NSString *)outputDirectory;

/// Writes a JSON object to `name` in the output directory.
+ (void)writeJSON:(id)object toFile:(NSString *)name;

/// Writes data to `name` (which may contain subdirectories) in the output directory.
+ (void)writeData:(NSData *)data toFile:(NSString *)name;

/// A recorder for one test. Steps go to traces/<suite>.jsonl.
+ (instancetype)recorderForTest:(XCTestCase *)test;

/// Records a value under a key. Values are normalized to JSON: expressions and
/// predicates by description, colors by RGBA components, NSValues of known
/// structs by their fields, numbers as numbers.
- (void)record:(NSString *)key value:(nullable id)value;

/// Runs the block and records its result, or the exception it raises.
- (void)record:(NSString *)key block:(id _Nullable (^)(void))block;

/// The JSON form of a value, as `-record:value:` stores it.
+ (id)normalize:(nullable id)value;

@end

NS_ASSUME_NONNULL_END
