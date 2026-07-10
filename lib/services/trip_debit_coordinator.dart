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
  appLogger.d(
    '→ Débito idViaje=$idViaje esQR=$esQR idCard=$idCard '
    'serie=$numeroSerieMonedero pasajes=$cantidadPasajes',
  );

  final loc = await nativeGpsService.getCurrentLocation();
  final lat = loc?.lat ?? 19.432608;
  final lon = loc?.lon ?? -99.133209;
  appLogger.d('GPS débito: lat=$lat lon=$lon (válido=${loc?.isValid})');

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
