import 'package:flutter/foundation.dart';

/// Tiny logging facade.
///
/// `print` is banned by the project's lint rules; production code logs through
/// this class instead so that logging can later be redirected to a file or a
/// crash-reporting service without touching any other class.
class AppLogger {
  const AppLogger(this.tag);

  final String tag;

  static const bool _verbose = kDebugMode;

  void info(String message) => _write('INFO', message);
  void warn(String message) => _write('WARN', message);
  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _write('ERROR', message, error: error, stackTrace: stackTrace);

  void _write(String level, String message, {Object? error, StackTrace? stackTrace}) {
    if (!_verbose && level == 'INFO') return;
    final buffer = StringBuffer('[$level] $tag: $message');
    if (error != null) buffer.write(' | error=$error');
    if (stackTrace != null) buffer.write('\n$stackTrace');
    debugPrint(buffer.toString());
  }
}
