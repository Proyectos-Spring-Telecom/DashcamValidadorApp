import 'package:dio/dio.dart';
import '../utils/logger.dart';

/// Servicio centralizado para manejo de errores
/// Proporciona mensajes de error consistentes y localizados
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  /// Login: 401/404 no enumeran usuario ni muestran "sesión expirada".
  String handleLoginError(dynamic error) {
    if (error is DioException && error.response != null) {
      final statusCode = error.response!.statusCode;
      final serverMessage = _extractServerMessage(error.response?.data) ?? '';
      final lower = serverMessage.toLowerCase();

      if (statusCode == 429 ||
          lower.contains('throttlerexception') ||
          lower.contains('too many requests')) {
        return 'Intentos excedidos, por favor espera unos minutos y vuelve a intentarlo.';
      }
      if (lower.contains('bloqueada')) {
        return serverMessage;
      }
      if (statusCode == 401 || statusCode == 404) {
        return 'Credenciales inválidas';
      }
    }
    return handleError(error);
  }

  /// Procesa un error y retorna un mensaje amigable para el usuario
  String handleError(dynamic error, {String? defaultMessage}) {
    if (error is DioException) {
      return _handleDioError(error);
    }
    appLogger.e('Error capturado');

    if (error is FormatException) {
      return 'Error de formato de datos. Por favor, intenta nuevamente.';
    }

    if (error is TypeError) {
      return 'Error de tipo de datos. Por favor, contacta al soporte.';
    }

    return defaultMessage ?? 'Ha ocurrido un error inesperado. Por favor, intenta nuevamente.';
  }

  /// Maneja errores específicos de Dio
  String _handleDioError(DioException error) {
    // Intentar obtener mensaje del servidor
    final serverMessage = _extractServerMessage(error.response?.data);

    if (error.response != null) {
      final statusCode = error.response!.statusCode;

      switch (statusCode) {
        case 400:
          return serverMessage ?? 'Solicitud inválida. Verifica los datos ingresados.';
        case 401:
          return serverMessage ?? 'Sesión expirada. Por favor, inicia sesión nuevamente.';
        case 403:
          return serverMessage ?? 'No tienes permisos para realizar esta acción.';
        case 404:
          return serverMessage ?? 'Recurso no encontrado.';
        case 409:
          return serverMessage ?? 'Conflicto: El recurso ya existe o está en uso.';
        case 422:
          return serverMessage ?? 'Datos inválidos. Verifica la información ingresada.';
        case 500:
          return 'Error del servidor. Por favor, intenta más tarde.';
        case 502:
        case 503:
        case 504:
          return 'Servicio temporalmente no disponible. Por favor, intenta más tarde.';
        default:
          return serverMessage ?? 'Error en la comunicación con el servidor.';
      }
    }

    // Errores de conexión
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Tiempo de espera agotado. Verifica tu conexión a internet.';
      case DioExceptionType.connectionError:
        return 'Error de conexión. Verifica tu conexión a internet.';
      case DioExceptionType.badResponse:
        return 'Respuesta inválida del servidor.';
      case DioExceptionType.cancel:
        return 'Operación cancelada.';
      case DioExceptionType.badCertificate:
        return 'Error de certificado de seguridad.';
      case DioExceptionType.unknown:
        return 'Error de conexión. Verifica tu conexión a internet.';
    }
  }

  static bool _pareceErrorDeMotor(String text) {
    final lower = text.toLowerCase();
    return lower.contains('queryfailed') ||
        lower.contains('sql syntax') ||
        lower.contains('unknown column') ||
        lower.contains('duplicate entry') ||
        lower.contains('econnreset') ||
        lower.contains('econnrefused') ||
        lower.contains('sqlstate');
  }

  /// Extrae el mensaje de error del servidor
  String? _extractServerMessage(dynamic data) {
    if (data == null) return null;

    if (data is String) {
      return _pareceErrorDeMotor(data) ? null : data;
    }

    if (data is Map<String, dynamic>) {
      final message = data['message'] as String? ??
          data['error'] as String? ??
          data['errorMessage'] as String? ??
          data['msg'] as String?;
      if (message == null || _pareceErrorDeMotor(message)) return null;
      return message;
    }

    return null;
  }

  /// Obtiene un mensaje de error específico para operaciones
  String getOperationErrorMessage(String operation) {
    return 'Error al $operation. Por favor, intenta nuevamente.';
  }
}

/// Instancia global del servicio de manejo de errores
final errorHandler = ErrorHandlerService();

