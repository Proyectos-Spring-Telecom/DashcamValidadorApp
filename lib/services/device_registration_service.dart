import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/device_service.dart';
import '../services/error_handler_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

/// Servicio dedicado para el registro de validador
/// Separado de AuthController para mejor separación de responsabilidades
/// 
/// El backend PATCH /usuarios/actualizar/validador actualiza la serie del validador en el usuario
class DeviceRegistrationService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;

  /// Actualiza el validador del usuario logueado
  /// 
  /// Retorna true si la actualización fue exitosa, false en caso contrario
  Future<bool> registerDevice(String userName, int clienteId) async {
    try {
      appLogger.i('Actualizando validador para usuario: $userName (cliente: $clienteId)');

      // Obtener el ID único del validador (deviceId)
      final validadorId = await DeviceService.getDeviceId();
      // ignore: avoid_print
      print('========== DEVICE ID / validadorId ==========');
      // ignore: avoid_print
      print('Origen : PATCH actualizar/validador');
      // ignore: avoid_print
      print('Valor  : $validadorId');
      // ignore: avoid_print
      print('=============================================');
      appLogger.i(
        '🆔 Device ID / validadorId (PATCH actualizar/validador) = $validadorId',
      );

      if (validadorId.isEmpty) {
        appLogger.w('No se pudo obtener ValidadorId, omitiendo actualización de validador');
        return false;
      }

      appLogger.i('Asociando validador al usuario: $userName');

      final response = await _httpService.dio.patch(
        AppConfig.endpointUpdateValidador,
        data: {
          'userName': userName,
          'validadorId': validadorId,
        },
      );

      // Verificar si la respuesta es exitosa
      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('✅ Validador actualizado exitosamente para usuario: $userName');
        return true;
      } else {
        appLogger.w('Respuesta inesperada al actualizar validador: ${response.statusCode}');
        return false;
      }
    } on DioException catch (e) {
      // Manejar específicamente el error 404 (usuario no encontrado)
      if (e.response?.statusCode == 404) {
        final responseText = e.response?.data?.toString() ?? '';
        appLogger.w(
          'Usuario no encontrado en el servidor (404). '
          'Mensaje del servidor: $responseText'
        );
        return false;
      }
      
      // Para otros errores, loguear como error
      final errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error al actualizar validador: $errorMessage', e);
      return false;
    } catch (e) {
      appLogger.e('Error inesperado al actualizar validador', e);
      return false;
    }
  }

  /// Obtiene el último mensaje de error
  String getLastErrorMessage() {
    return 'Error al actualizar el validador';
  }
}

/// Instancia global del servicio de registro de dispositivos
final deviceRegistrationService = DeviceRegistrationService();

