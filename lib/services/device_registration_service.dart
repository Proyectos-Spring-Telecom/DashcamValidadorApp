import '../services/device_service.dart';
import '../utils/logger.dart';

/// Ya no reasigna el validador en cada login.
/// La asignación queda en admin (WebApp) / PIN binding. El login solo lee el Android ID.
class DeviceRegistrationService {
  Future<bool> registerDevice(String userName, int clienteId) async {
    final validadorId = await DeviceService.getDeviceId();
    appLogger.i(
      'Login sin PATCH /usuarios/actualizar/validador. '
      'Usuario=$userName cliente=$clienteId deviceId=$validadorId',
    );
    return true;
  }

  String getLastErrorMessage() {
    return 'Error al actualizar el validador';
  }
}

final deviceRegistrationService = DeviceRegistrationService();
