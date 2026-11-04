// Based on platform/darwin/src/MLNLoggingConfiguration.mm at ios-v7.0.0

#import <MaplibreNativeC/maplibre_native_c.h>

#import "MLNFFI.h"
#import "MLNLoggingConfiguration_Private.h"

#ifndef MLN_LOGGING_DISABLED
#if __has_builtin(__builtin_os_log_format)
#import <os/log.h>
#endif

// The names of mln::Event, which the core used in these messages.
static const char *MLNLogEventName(mln_log_event event) {
  static const char *const names[] = {
      "General", "Setup", "Shader", "ParseStyle", "ParseTile", "Render",
      "Style", "Database", "HttpRequest", "Sprite", "Image", "GraphicsBackend",
      "JNI", "Android", "Crash", "Glyph", "Timing",
  };
  return event < sizeof(names) / sizeof(names[0]) ? names[event] : "General";
}

// Return true not to print messages at core level, and filter at platform level.
static bool MLNCoreLoggingCallback(void *userData, mln_log_severity severity, mln_log_event event,
                                   int64_t code, mln_buffer_view text) {
  NSString *message = [NSString stringWithFormat:@"[event]:%s [code]:%lld [message]:%@",
                                                 MLNLogEventName(event), code,
                                                 MLNFFIStringFromBufferView(text) ?: @""];
  switch (severity) {
    case MLN_LOG_SEVERITY_INFO:
      MLNLogInfo(message);
      break;
    case MLN_LOG_SEVERITY_WARNING:
      MLNLogWarning(message);
      break;
    case MLN_LOG_SEVERITY_ERROR:
      MLNLogError(message);
      break;
    default:
      MLNLogDebug(message);
      break;
  }
  return true;
}

@implementation MLNLoggingConfiguration

+ (instancetype)sharedConfiguration {
  static dispatch_once_t once;
  static id sharedConfiguration;
  dispatch_once(&once, ^{
    sharedConfiguration = [[self alloc] init];
    ((MLNLoggingConfiguration *)sharedConfiguration).handler = nil;
  });
  return sharedConfiguration;
}

- (id)init {
  if (self = [super init]) {
    mln_log_handler handler = {sizeof(mln_log_handler)};
    handler.callback = MLNCoreLoggingCallback;
    mln_diagnostic diagnostic = {sizeof(mln_diagnostic)};
    mln_log_set_callback(&handler, &diagnostic);
  }
  return self;
}

- (void)setHandler:(void (^)(MLNLoggingLevel, NSString *, NSUInteger, NSString *))handler {
  if (!handler) {
    _handler = [self defaultBlockHandler];
  } else {
    _handler = handler;
  }
}

- (void)logCallingFunction:(const char *)callingFunction
              functionLine:(NSUInteger)functionLine
               messageType:(MLNLoggingLevel)type
                    format:(id)messageFormat, ... {
  va_list formatList;
  va_start(formatList, messageFormat);
  NSString *formattedMessage = [[NSString alloc] initWithFormat:messageFormat arguments:formatList];
  va_end(formatList);

  _handler(type, @(callingFunction), functionLine, formattedMessage);
}

- (MLNLoggingBlockHandler)defaultBlockHandler {
  MLNLoggingBlockHandler maplibreHandler = ^(MLNLoggingLevel level, NSString *fileName,
                                             NSUInteger line, NSString *message) {
    static dispatch_once_t once;
    static os_log_t info_log;
#if MLN_LOGGING_ENABLE_DEBUG
    static os_log_t debug_log;
#endif
    static os_log_t error_log;
    static os_log_t fault_log;
    static os_log_type_t log_types[] = {OS_LOG_TYPE_DEFAULT, OS_LOG_TYPE_INFO,
#if MLN_LOGGING_ENABLE_DEBUG
                                        OS_LOG_TYPE_DEBUG,
#endif
                                        OS_LOG_TYPE_ERROR, OS_LOG_TYPE_FAULT};
    constexpr const char *const subsystem = "org.maplibre.Native";
    dispatch_once(&once, ^{
      info_log = os_log_create(subsystem, "INFO");
#if MLN_LOGGING_ENABLE_DEBUG
      debug_log = os_log_create(subsystem, "DEBUG");
#endif
      error_log = os_log_create(subsystem, "ERROR");
      fault_log = os_log_create(subsystem, "FAULT");
    });

    os_log_t maplibre_log;
    switch (level) {
      case MLNLoggingLevelInfo:
      case MLNLoggingLevelWarning:
        maplibre_log = info_log;
        break;
#if MLN_LOGGING_ENABLE_DEBUG
      case MLNLoggingLevelDebug:
        maplibre_log = debug_log;
        break;
#endif
      case MLNLoggingLevelError:
        maplibre_log = error_log;
        break;
      case MLNLoggingLevelFault:
        maplibre_log = fault_log;
        break;
      case MLNLoggingLevelNone:
      default:
        break;
    }

    os_log_type_t logType = log_types[level];
    os_log_with_type(maplibre_log, logType, "%@ - %lu: %@", fileName, (unsigned long)line, message);
  };

  return maplibreHandler;
}

@end
#endif
