import 'package:pretty_dio_logger/pretty_dio_logger.dart';
import 'package:flutter/foundation.dart';

final PrettyDioLogger prettyDioLogger = PrettyDioLogger(
  requestHeader: true,
  requestBody: true,
  responseBody: true,
  responseHeader: false,
  error: true,
  compact: true,
  maxWidth: 90,
  enabled: kDebugMode,
  filter: (options, args) {
    // don't print requests with uris containing '/posts' 
    if (options.path.contains('/posts')) {
      return false;
    }
    // don't print responses with unit8 list data
    return !args.isResponse || !args.hasUint8ListData;
  },
);
