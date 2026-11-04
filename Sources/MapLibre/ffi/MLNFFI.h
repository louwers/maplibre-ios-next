// The bridge between the Objective-C SDK and the MapLibre Native FFI C API.
//
// MapLibre iOS was written against mbgl::Map, which lives on the main thread
// and answers every call synchronously. The C API runs each map on its
// runtime's worker thread and answers asynchronously, in submission order. The
// bridge restores the classic model:
//
// - `-[MLNFFIMap call:...]` submits a call and blocks until it completes.
//   Calls complete in order, so a query sees every earlier command.
// - Map events are copied on the worker thread and queued per map. On the main
//   thread, every completed call drains that queue before it returns, so
//   observers see events (camera changes, style loading, ...) during the call
//   that caused them, as they do with mbgl. Events that arrive later (animation
//   frames, tile loads) are drained asynchronously.
//
// Never block on a call from inside a library callback, and never dispatch
// synchronously to the main queue from one.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNGeometry.h"

NS_ASSUME_NONNULL_BEGIN

/// Submits one C API call with the given completion and diagnostic.
typedef mln_status (^MLNFFISubmit)(const mln_completion *completion,
                                   mln_diagnostic *diagnostic);
/// Copies what it needs out of a borrowed completion result. Runs on a library
/// thread.
typedef void (^MLNFFIConsume)(const mln_completion_result *result);

// MARK: - Values

/// A buffer view of the string's UTF-8 bytes. The string must outlive the call.
FOUNDATION_EXTERN mln_buffer_view MLNFFIBufferView(NSString *_Nullable string);
FOUNDATION_EXTERN NSString *_Nullable MLNFFIStringFromBufferView(mln_buffer_view view);
FOUNDATION_EXTERN NSData *_Nullable MLNFFIDataFromBufferView(mln_buffer_view view);
/// The JSON value in the buffer, which may be a fragment (string, number, ...).
FOUNDATION_EXTERN id _Nullable MLNFFIJSONObjectFromBufferView(mln_buffer_view view);
/// Serializes a JSON value, which may be a fragment. NSNull serializes to `null`.
FOUNDATION_EXTERN NSString *MLNFFIJSONStringFromObject(id _Nullable object);

FOUNDATION_EXTERN mln_lat_lng MLNFFILatLng(CLLocationCoordinate2D coordinate);
FOUNDATION_EXTERN CLLocationCoordinate2D MLNFFICoordinate(mln_lat_lng latLng);
FOUNDATION_EXTERN mln_lat_lng_bounds MLNFFILatLngBounds(MLNCoordinateBounds bounds);
FOUNDATION_EXTERN MLNCoordinateBounds MLNFFICoordinateBounds(mln_lat_lng_bounds bounds);

/// A message describing a failed status for logs and exceptions.
FOUNDATION_EXTERN NSString *MLNFFIStatusDescription(mln_status status);

// MARK: - Events

/// A copy of one `mln_runtime_event`, safe to keep after the callback returns.
@interface MLNFFIEvent : NSObject
@property (nonatomic, readonly) mln_runtime_event_type type;
@property (nonatomic, readonly) mln_runtime_event_source_type sourceType;
@property (nonatomic, readonly) uint64_t source;
@property (nonatomic, readonly) uint64_t generation;
@property (nonatomic, readonly) uint32_t code;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly) mln_runtime_event_payload_type payloadType;
/// The payload; pointer members (glyph font stacks, sprite strings) are cleared.
@property (nonatomic, readonly) mln_runtime_event_payload payload;
@property (nonatomic, readonly, copy, nullable) NSArray<NSString *> *fontStack;
@property (nonatomic, readonly, copy, nullable) NSString *spriteIdentifier;
@property (nonatomic, readonly, copy, nullable) NSString *spriteURL;
@end

@class MLNFFIMap;

@protocol MLNFFIMapEventObserver <NSObject>
/// Called on the main thread, in event order.
- (void)ffiMap:(MLNFFIMap *)map didReceiveEvent:(MLNFFIEvent *)event;
@end

@protocol MLNFFIRuntimeEventObserver <NSObject>
/// Runtime (offline region) events. Called on the main thread, in event order.
- (void)ffiRuntimeDidReceiveEvent:(MLNFFIEvent *)event;
@end

// MARK: - Runtime

@interface MLNFFIRuntime : NSObject

/// The process-wide runtime, created on first use. Every map, the offline
/// storage, and every snapshotter share it, as classic MapLibre iOS shares one
/// database file source.
+ (instancetype)sharedRuntime;

/// The cache database the shared runtime uses. Set before first use of
/// `sharedRuntime`; nil keeps the cache in memory.
+ (void)setCachePath:(nullable NSString *)path;
+ (nullable NSString *)cachePath;

/// Supplies the cache path when none was set: MLNOfflineStorage registers the
/// classic database location (or MLNOfflineStorageDatabasePath) here, so the
/// runtime opens it no matter which object creates the runtime first.
+ (void)setDefaultCachePathProvider:(nullable NSString *_Nullable (^)(void))provider;

@property (nonatomic, readonly) mln_runtime handle;

/// Blocks until the runtime-level call completes. Returns its status and
/// writes its diagnostic to `message`.
- (mln_status)call:(MLNFFISubmit)submit
           consume:(nullable MLNFFIConsume)consume
           message:(NSString *_Nullable *_Nullable)message;

/// Submits a runtime-level call and calls `completion` with its result on the
/// main queue. `consume` runs first, on a library thread.
- (void)callAsync:(MLNFFISubmit)submit
          consume:(nullable MLNFFIConsume)consume
       completion:(nullable void (^)(mln_status status, NSString *message))completion;

@property (nonatomic, weak, nullable) id<MLNFFIRuntimeEventObserver> runtimeEventObserver;

@end

// MARK: - Map

@interface MLNFFIMap : NSObject

/// Creates a map on the shared runtime and waits until it exists. Returns nil
/// and logs if the C API refuses.
- (nullable instancetype)initWithSize:(CGSize)size
                          scaleFactor:(double)scaleFactor
                                 mode:(mln_map_mode)mode;
- (instancetype)init NS_UNAVAILABLE;

/// A hidden static map with an empty style, used to normalize and validate the
/// properties of layers that are not part of any style yet.
+ (instancetype)scratchMap;

@property (nonatomic, readonly) mln_map handle;
@property (nonatomic, readonly) double scaleFactor;
@property (nonatomic, weak, nullable) id<MLNFFIMapEventObserver> eventObserver;

/// Blocks until the call completes, then delivers pending events if called on
/// the main thread. Returns the call's terminal status (or the submit status
/// if the call was refused) and writes its diagnostic to `message`.
- (mln_status)call:(MLNFFISubmit)submit
           consume:(nullable MLNFFIConsume)consume
           message:(NSString *_Nullable *_Nullable)message;

/// Like `-call:consume:message:`, but logs a failure instead of returning it.
- (BOOL)perform:(NSString *)label submit:(MLNFFISubmit)submit;

/// Submits a call without waiting. Failures are logged.
- (void)post:(NSString *)label submit:(MLNFFISubmit)submit;

/// Submits a call and calls `completion` on the main queue when it completes.
- (void)callAsync:(MLNFFISubmit)submit
          consume:(nullable MLNFFIConsume)consume
       completion:(nullable void (^)(mln_status status, NSString *message))completion;

/// The latest published state. Valid once the map exists; after a blocking
/// call it includes that call.
- (mln_map_snapshot)snapshot;

/// Delivers queued events now. Main thread only.
- (void)drainEvents;

/// The event types that a blocking call on the main thread delivers before it
/// returns: those classic's core raised within the call (camera changes, the
/// start of a style load). Other events wait for the next turn of the main
/// queue, as classic delivered them after the call. Settable around a call
/// whose other events classic raised synchronously, such as loading a style
/// from JSON.
@property (nonatomic) mln_runtime_event_flags synchronousEventTypes;

/// Releases the native map. Further calls fail with an invalid-state status.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
