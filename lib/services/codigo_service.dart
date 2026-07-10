import '../app/auth.dart';
import '../config/app_config.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../utils/logger.dart';

/// Servicio para gestionar el código del operador
class CodigoService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;

  static String? _lastError;

  /// Último mensaje de error
  static String? get lastError => _lastError;

  /// Actualiza el código del operador en el servidor
  Future<bool> updateOperatorCodigo({
    required String userName,
    required String codigo,
  }) async {
    try {
      _lastError = null;
      appLogger.i('Actualizando código para usuario: $userName');

      // Obtener el token de autenticación
      final token = auth.token;
      if (token == null || token.isEmpty) {
        _lastError = 'No hay sesión activa';
        appLogger.w('Intento de actualizar código sin sesión activa');
        return false;
      }

      final response = await _httpService.dio.patch(
        AppConfig.endpointGeneratePin,
        data: {
          'userName': userName,
          'codigohash': codigo, // El servidor se encarga del hash
        },
      );

      // Verificar si la respuesta es exitosa
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('Código actualizado exitosamente');
        return true;
      } else {
        _lastError = 'Error al actualizar código';
        appLogger.w('Respuesta inesperada al actualizar código: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _lastError = _errorHandler.handleError(e, defaultMessage: 'Error al actualizar código');
      appLogger.e('Error al actualizar código', e);
      return false;
    }
  }

  /// Valida que un código tenga el formato correcto
  /// Soporta longitudes de 6 u 8 dígitos según AppConfig
  static bool isValidCodigo(String codigo, {int? requiredLength}) {
    // Si no se especifica longitud, verificar que sea una de las permitidas
    if (requiredLength == null) {
      if (!AppConfig.allowedCodigoLengths.contains(codigo.length)) {
        return false;
      }
    } else {
      // Verificar longitud específica
      if (codigo.length != requiredLength) {
        return false;
      }
    }

    // Verificar que solo contenga dígitos
    if (!RegExp(r'^\d+$').hasMatch(codigo)) {
      return false;
    }

    return true;
  }

  /// Valida que dos códigos coincidan
  static bool codigosMatch(String codigo1, String codigo2) {
    return codigo1 == codigo2;
  }

  /// Obtiene información sobre los requisitos del código
  static Map<String, dynamic> getCodigoRequirements() {
    return {
      'allowedLengths': AppConfig.allowedCodigoLengths,
      'charactersAllowed': 'Solo números (0-9)',
      'minLength': AppConfig.allowedCodigoLengths.first,
      'maxLength': AppConfig.allowedCodigoLengths.last,
      'mustMatch': true,
      'description':
          'El código debe tener ${AppConfig.allowedCodigoLengths.join(" o ")} dígitos numéricos y debe confirmarse ingresándolo dos veces',
    };
  }

  /// Limpia el último error
  static void clearLastError() {
    _lastError = null;
  }
}

/// Instancia global del servicio de código
final codigoService = CodigoService();

