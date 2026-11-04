// Based on platform/darwin/src/MLNFoundation_Private.h at ios-v7.0.0
//
// Classic declared MLNInitializeRunLoop() here, which set up the core's run
// loop on the main thread. The C API runs its own threads, so it is gone.

#import "MLNFoundation.h"


/* Using a compound statement (GNU Extension, supported by clang) */
#define MLN_OBJC_DYNAMIC_CAST(object, type)                                       \
  ({                                                                              \
    __typeof__(object) temp##__LINE__ = (object);                                 \
    (type *)([temp##__LINE__ isKindOfClass:[type class]] ? temp##__LINE__ : nil); \
  })

#define MLN_OBJC_DYNAMIC_CAST_AS_PROTOCOL(object, proto)                                      \
  ({                                                                                          \
    __typeof__(object) temp##__LINE__ = (object);                                             \
    (id<proto>)([temp##__LINE__ conformsToProtocol:@protocol(proto)] ? temp##__LINE__ : nil); \
  })
