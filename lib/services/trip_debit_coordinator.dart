import 'native_gps_service.dart';
import 'wallet_service.dart';
import '../utils/logger.dart';

/// GPS + llamada unificada a [WalletService.debitTripTransaction].
Future<DebitTripTransactionResult> executeTripDebit({
  required int idViaje,
  String idCard = '',
  String numeroSerieMonedero = '',
  bool esQR = false,
  bool esMultiple = false,
  int cantidadPasajes = 0,
}) async {
  appLogger.d('Débito de viaje esQR=$esQR pasajes=$cantidadPasajes');

  final loc = await nativeGpsService.getCurrentLocation();
  final lat = loc?.lat;
  final lon = loc?.lon;
  if (loc == null ||
      lat == null ||
      lon == null ||
      !loc.isValid ||
      lat.isNaN ||
      lon.isNaN ||
      (lat == 0.0 && lon == 0.0) ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    appLogger.w('Débito cancelado: GPS no disponible');
    return DebitTripTransactionResult(
      success: false,
      errorMessage: 'Ubicación GPS no disponible',
    );
  }

  final result = await walletService.debitTripTransaction(
    idCard: idCard,
    latitud: lat,
    longitud: lon,
    idViaje: idViaje,
    numeroSerieMonedero: numeroSerieMonedero,
    esQR: esQR,
    esMultiple: esMultiple,
    cantidadPasajes: cantidadPasajes,
  );

  appLogger.d(
    result.success
        ? '✓ Débito OK'
        : '✗ Débito falló: ${result.errorMessage ?? "?"}',
  );
  return result;
}
