import '../utils/logger.dart';

/// El login reasigna el camión en el API. Este método ya no hace PATCH.
class DeviceRegistrationService {
  Future<bool> registerDevice(String userName, int clienteId) async {
    appLogger.i('Login sin PATCH de validador');
    return true;
  }

  String getLastErrorMessage() {
    return 'Error al actualizar el validador';
  }
}

final deviceRegistrationService = DeviceRegistrationService();
