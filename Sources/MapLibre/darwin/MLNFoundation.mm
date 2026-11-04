// Based on platform/darwin/src/MLNFoundation.mm at ios-v7.0.0
//
// Classic defined MLNInitializeRunLoop() here, which created the core's run
// loop on the main thread. The C API's runtime runs its own threads.

#import "MLNFoundation_Private.h"
