import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as logger_pkg;

/// Logger estructurado para la aplicación
/// Proporciona diferentes niveles de logging con formato consistente
class AppLogger {
  static final AppLogger _instance = AppLogger._internal();
  factory AppLogger() => _instance;
  AppLogger._internal();

  logger_pkg.Logger? _logger;

  logger_pkg.Logger get logger {
    _logger ??= logger_pkg.Logger(
      printer: logger_pkg.PrettyPrinter(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 120,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      level: kDebugMode ? logger_pkg.Level.debug : logger_pkg.Level.warning,
    );
    return _logger!;
  }

  /// Log de debug (solo en desarrollo)
  void d(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log de información
  void i(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log de advertencia
  void w(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log de error
  void e(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.e(message, error: error, stackTrace: stackTrace);
  }

  /// Log de error fatal
  void f(String message, [dynamic error, StackTrace? stackTrace]) {
    logger.f(message, error: error, stackTrace: stackTrace);
  }
}

/// Instancia global del logger
final appLogger = AppLogger();

