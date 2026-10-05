import 'dart:math';
import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../services/device_service.dart';
import '../services/device_api_service.dart';
import '../services/storage_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';
import '../utils/nfc_result_codes.dart';

/// Resultado de la operación de recarga de monedero
class RechargeWalletResult {
  final bool success;
  final String? errorMessage;

  RechargeWalletResult({required this.success, this.errorMessage});
}

/// Resultado del débito en viaje (NFC / QR)
class DebitTripTransactionResult {
  final bool success;
  final String? errorMessage;

  DebitTripTransactionResult({required this.success, this.errorMessage});
}

/// Modelo para la respuesta de creación de transacción de débito
class DebitTransactionResponse {
  final int id;
  final String nombre;

  DebitTransactionResponse({
    required this.id,
    required this.nombre,
  });

  factory DebitTransactionResponse.fromJson(Map<String, dynamic> json) {
    return DebitTransactionResponse(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
    );
  }
}

class WalletService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;
  final StorageService _storage = StorageService();
  final Map<String, String> _pendingIdempotencyKeys = {};

  String _newUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  bool _coordenadaUsable(double lat, double lon) {
    if (lat.isNaN || lon.isNaN || lat.isInfinite || lon.isInfinite) return false;
    if (lat == 0.0 && lon == 0.0) return false;
    if (lat.abs() > 90 || lon.abs() > 180) return false;
    return true;
  }

  /// Misma llave mientras el tap no termine (reintento). Nuevo tap = nueva llave.
  String _claveIdempotencia(String fingerprint) {
    return _pendingIdempotencyKeys.putIfAbsent(fingerprint, _newUuidV4);
  }

  void _liberarClave(String fingerprint) {
    _pendingIdempotencyKeys.remove(fingerprint);
  }

  /// Recarga el monedero vía API (endpointRechargeWallet).
  /// Usa numeroSerieValidador del storage o del dispositivo, GPS para lat/lon, idMetodoPago: 1.
  Future<RechargeWalletResult> rechargeWallet({
    required double monto,
    required double latitudInicial,
    required double longitudInicial,
    required String numeroSerieMonedero,
  }) async {
    try {
      if (!_coordenadaUsable(latitudInicial, longitudInicial)) {
        appLogger.w('GPS no disponible o inválido en recarga');
        return RechargeWalletResult(
          success: false,
          errorMessage: 'Ubicación GPS no disponible',
        );
      }
      final lat = latitudInicial;
      final lon = longitudInicial;

      final latRounded = double.parse(lat.toStringAsFixed(6));
      final lonRounded = double.parse(lon.toStringAsFixed(6));

      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
        }
      }
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('No se pudo obtener numeroSerieValidador');
        return RechargeWalletResult(success: false, errorMessage: 'Validador no configurado');
      }

      final montoValue = (monto % 1 == 0) ? monto.toInt() : monto;
      final fingerprint = 'recarga|$numeroSerieMonedero|$montoValue';
      final claveIdempotencia = _claveIdempotencia(fingerprint);

      final body = {
        'idTipoTransaccion': 1,
        'monto': montoValue,
        'latitudInicial': latRounded,
        'longitudInicial': lonRounded,
        'numeroSerieMonedero': numeroSerieMonedero,
        'numeroSerieValidador': numeroSerieValidador,
        'idMetodoPago': 1,
        'claveIdempotencia': claveIdempotencia,
      };

      appLogger.d('Enviando recarga de monedero (serie omitida)');

      final response = await _httpService.dio.post(
        AppConfig.endpointRechargeWallet,
        data: body,
      );

      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        _liberarClave(fingerprint);
        appLogger.i('✅ Recarga de monedero realizada correctamente');
        return RechargeWalletResult(success: true);
      }
      final msg = response.data is Map ? (response.data as Map)['message']?.toString() : null;
      appLogger.w('Respuesta inesperada recarga: ${response.statusCode}');
      return RechargeWalletResult(success: false, errorMessage: msg ?? 'Error al recargar');
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al recargar monedero: $msg');
      if (e.response != null) {
        appLogger.e('El servidor rechazó la operación');
      }
      return RechargeWalletResult(success: false, errorMessage: msg ?? 'Error de conexión');
    } catch (e) {
      appLogger.e('Error inesperado al recargar monedero');
      return RechargeWalletResult(success: false, errorMessage: e.toString());
    }
  }

  DebitTripTransactionResult? _parseDebitResponse(dynamic data, int? statusCode) {
    if (data is! Map) return null;
    final map = Map<String, dynamic>.from(data);

    final successFlag = map['success'];
    if (successFlag is bool && !successFlag) {
      final msg = map['message']?.toString() ??
          map['error']?.toString() ??
          map['errorMessage']?.toString();
      return DebitTripTransactionResult(
        success: false,
        errorMessage: NfcResultCodes.friendlyMessage(
          msg ?? 'Error al procesar cobro',
        ),
      );
    }

    final result = map['result'];
    if (result is num && result.toInt() != 0) {
      final msg = map['message']?.toString();
      return DebitTripTransactionResult(
        success: false,
        errorMessage: NfcResultCodes.friendlyMessage(
          msg ?? NfcResultCodes.message(result.toInt()),
        ),
      );
    }

    if (statusCode != null && statusCode >= 400) {
      final msg = map['message']?.toString();
      return DebitTripTransactionResult(
        success: false,
        errorMessage: NfcResultCodes.friendlyMessage(
          msg ?? 'Error al procesar cobro',
        ),
      );
    }

    return null;
  }

  /// Débito en viaje activo (POST endpointDebitTransaction).
  /// [idCard] = UID NFC; [numeroSerieMonedero] desde monedero o vacío si solo NFC/QR pendiente.
  Future<DebitTripTransactionResult> debitTripTransaction({
    required String idCard,
    required double latitud,
    required double longitud,
    required int idViaje,
    String numeroSerieMonedero = '',
    bool esQR = false,
    bool esMultiple = false,
    int cantidadPasajes = 0,
  }) async {
    try {
      if (!_coordenadaUsable(latitud, longitud)) {
        appLogger.w('GPS no disponible o inválido en débito');
        return DebitTripTransactionResult(
          success: false,
          errorMessage: 'Ubicación GPS no disponible',
        );
      }
      final lat = latitud;
      final lon = longitud;

      final latRounded = double.parse(lat.toStringAsFixed(6));
      final lonRounded = double.parse(lon.toStringAsFixed(6));

      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
        }
      }
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('No se pudo obtener numeroSerieValidador para débito viaje');
        return DebitTripTransactionResult(success: false, errorMessage: 'Validador no configurado');
      }

      final fingerprint = 'debito|$idCard|$idViaje|$esQR|$esMultiple|$cantidadPasajes';
      final claveIdempotencia = _claveIdempotencia(fingerprint);

      final body = {
        'latitud': latRounded,
        'longitud': lonRounded,
        'numeroSerieMonedero': numeroSerieMonedero,
        'idCard': idCard,
        'numeroSerieValidador': numeroSerieValidador,
        'idViaje': idViaje,
        'esQR': esQR,
        'esMultiple': esMultiple,
        'cantidadPasajes': cantidadPasajes,
        'claveIdempotencia': claveIdempotencia,
      };

      appLogger.d('Débito viaje (payload omitido)');

      final response = await _httpService.dio.post(
        AppConfig.endpointDebitTransaction,
        data: body,
      );

      final parsed = _parseDebitResponse(response.data, response.statusCode);
      if (parsed != null) {
        if (parsed.success) _liberarClave(fingerprint);
        return parsed;
      }

      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        _liberarClave(fingerprint);
        appLogger.i('✅ Débito viaje exitoso');
        appLogger.d('← HTTP ${response.statusCode} débito OK');
        return DebitTripTransactionResult(success: true);
      }
      final msg = response.data is Map ? (response.data as Map)['message']?.toString() : null;
      appLogger.d('← HTTP ${response.statusCode} débito (cuerpo omitido)');
      return DebitTripTransactionResult(
        success: false,
        errorMessage: NfcResultCodes.friendlyMessage(
          msg ?? 'Error al procesar cobro',
        ),
      );
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error débito viaje');
      if (e.response != null) {
        final parsed = _parseDebitResponse(e.response?.data, e.response?.statusCode);
        if (parsed != null) return parsed;
      }
      return DebitTripTransactionResult(
        success: false,
        errorMessage: NfcResultCodes.friendlyMessage(msg ?? 'Error de conexión'),
      );
    } catch (e) {
      appLogger.e('Error inesperado débito viaje');
      return DebitTripTransactionResult(success: false, errorMessage: e.toString());
    }
  }

  Future<MonederoInfo?> getWalletBySerie(String serie) async {
    try {
      final response = await _httpService.dio.get('${AppConfig.endpointWalletBySerie}/$serie');
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        return MonederoInfo.fromJson(data);
      }
      appLogger.w('Respuesta inesperada al consultar monedero: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      _errorHandler.handleError(e);
      appLogger.e('Error al obtener monedero');
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al obtener monedero');
      return null;
    }
  }

  Future<PassengerInfo?> getPassengerById(int id) async {
    try {
      appLogger.d('Consultando información del pasajero con id: $id');
      final response = await _httpService.dio.get('${AppConfig.endpointPassenger}/$id');
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data == null) {
          appLogger.w('Respuesta del servidor no contiene campo "data"');
          return null;
        }
        final passenger = PassengerInfo.fromJson(data);
        appLogger.i('Información del pasajero obtenida');
        return passenger;
      }
      appLogger.w('Respuesta inesperada al consultar pasajero: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al obtener pasajero: $msg');
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al obtener pasajero');
      return null;
    }
  }

  /// Inicia una transacción de débito para tarifa punto a punto o por metro
  /// (controlTransaccion: 1) - Primera lectura de tarjeta
  /// Retorna el ID de la transacción creada o null si hay error
  Future<int?> startTripDebit({
    required double amount,
    required double lat,
    required double lon,
    required String numeroSerieMonedero,
  }) async {
    try {
      // Validar que no sean NaN o Infinite
      if (lat.isNaN || lon.isNaN || lat.isInfinite || lon.isInfinite) {
        appLogger.e('Coordenadas GPS inválidas (NaN o Infinite)');
        return null;
      }

      final deviceId = await DeviceService.getDeviceId();
      
      // Formatear fechaHora en formato ISO 8601 UTC sin milisegundos
      final fechaHoraUtc = DateTime.now().toUtc();
      final fechaHora = '${fechaHoraUtc.year}-${fechaHoraUtc.month.toString().padLeft(2, '0')}-${fechaHoraUtc.day.toString().padLeft(2, '0')}T${fechaHoraUtc.hour.toString().padLeft(2, '0')}:${fechaHoraUtc.minute.toString().padLeft(2, '0')}:${fechaHoraUtc.second.toString().padLeft(2, '0')}Z';
      
      // Redondear coordenadas a 6 decimales
      final latRounded = double.parse(lat.toStringAsFixed(6));
      final lonRounded = double.parse(lon.toStringAsFixed(6));
      
      // Asegurar que los valores numéricos sean números (no strings)
      final montoValue = (amount % 1 == 0) ? amount.toInt() : amount.toDouble();
      
      final body = {
        'controlTransaccion': 1,
        'monto': montoValue,
        'latitudInicial': latRounded,
        'longitudInicial': lonRounded,
        'fechaHoraInicio': fechaHora,
        'numeroSerieMonedero': numeroSerieMonedero,
        'numeroSerieDispositivo': deviceId,
      };

      appLogger.i('Iniciando transacción de débito');

      final response = await _httpService.dio.post(
        AppConfig.endpointDebitTransaction,
        data: body,
      );

      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        // Parsear la respuesta
        final responseData = response.data;
        if (responseData is Map<String, dynamic> && responseData['data'] != null) {
          final transactionData = DebitTransactionResponse.fromJson(responseData['data'] as Map<String, dynamic>);
          appLogger.i('✅ Transacción de inicio creada exitosamente. ID: ${transactionData.id}');
          return transactionData.id;
        }
        appLogger.w('Respuesta inesperada: no contiene campo "data"');
        return null;
      }
      appLogger.w('Respuesta inesperada al iniciar transacción: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al iniciar transacción de débito: $msg');
      
      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('El servidor rechazó la operación');
      }
      
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al iniciar transacción de débito');
      return null;
    }
  }

  /// Finaliza una transacción de débito para tarifa punto a punto o por metro
  /// (controlTransaccion: 0) - Segunda lectura de tarjeta (cierre de viaje)
  /// Requiere el ID de la transacción creada en startTripDebit
  Future<bool> endTripDebit({
    required int idTransaccionDebito,
    required double amount,
    required double lat,
    required double lon,
    required String numeroSerieMonedero,
  }) async {
    try {
      // Validar que no sean NaN o Infinite
      if (lat.isNaN || lon.isNaN || lat.isInfinite || lon.isInfinite) {
        appLogger.e('Coordenadas GPS inválidas (NaN o Infinite)');
        return false;
      }

      final deviceId = await DeviceService.getDeviceId();
      
      // Formatear fechaHora en formato ISO 8601 UTC sin milisegundos
      final fechaHoraUtc = DateTime.now().toUtc();
      final fechaHora = '${fechaHoraUtc.year}-${fechaHoraUtc.month.toString().padLeft(2, '0')}-${fechaHoraUtc.day.toString().padLeft(2, '0')}T${fechaHoraUtc.hour.toString().padLeft(2, '0')}:${fechaHoraUtc.minute.toString().padLeft(2, '0')}:${fechaHoraUtc.second.toString().padLeft(2, '0')}Z';
      
      // Redondear coordenadas a 6 decimales
      final latRounded = double.parse(lat.toStringAsFixed(6));
      final lonRounded = double.parse(lon.toStringAsFixed(6));
      
      // Asegurar que los valores numéricos sean números (no strings)
      final montoValue = (amount % 1 == 0) ? amount.toInt() : amount.toDouble();
      
      final body = {
        'idTransaccionDebito': idTransaccionDebito,
        'monto': montoValue,
        'controlTransaccion': 0,
        'latitudFinal': latRounded,
        'longitudFinal': lonRounded,
        'fechaHoraFinal': fechaHora,
        'numeroSerieMonedero': numeroSerieMonedero,
        'numeroSerieDispositivo': deviceId,
      };

      appLogger.i('Finalizando transacción de débito');

      final response = await _httpService.dio.patch(
        AppConfig.endpointDebitTransactionUpdate,
        data: body,
      );

      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300) {
        appLogger.i('✅ Transacción de cierre completada exitosamente');
        return true;
      }
      appLogger.w('Respuesta inesperada al finalizar transacción: ${response.statusCode}');
      return false;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al finalizar transacción de débito: $msg');
      
      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('El servidor rechazó la operación');
      }
      
      return false;
    } catch (e) {
      appLogger.e('Error inesperado al finalizar transacción de débito');
      return false;
    }
  }
}

class MonederoInfo {
  final int id;
  final String numeroSerie;
  final double saldo;
  final String? fechaActivacion;
  final String? fechaCreacion;
  final String? fechaActualizacion;
  final int estatus;
  final int? idPasajero;
  final int idCliente;
  final String? idTipoPasajero;

  MonederoInfo({
    required this.id,
    required this.numeroSerie,
    required this.saldo,
    required this.fechaActivacion,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    required this.estatus,
    required this.idPasajero,
    required this.idCliente,
    required this.idTipoPasajero,
  });

  factory MonederoInfo.fromJson(Map<String, dynamic> json) {
    // Convertir idPasajero: 0 a null (el backend devuelve 0 cuando no hay pasajero)
    final idPasajeroValue = json['idPasajero'];
    final int? idPasajero = (idPasajeroValue != null && idPasajeroValue != 0) 
        ? (idPasajeroValue is int ? idPasajeroValue : int.tryParse(idPasajeroValue.toString()))
        : null;
    
    return MonederoInfo(
      id: json['id'] ?? 0,
      numeroSerie: json['numeroSerie'] ?? '',
      saldo: (json['saldo'] as num?)?.toDouble() ?? 0,
      fechaActivacion: json['fechaActivacion'],
      fechaCreacion: json['fechaCreacion'],
      fechaActualizacion: json['fechaActualizacion'],
      estatus: json['estatus'] ?? 0,
      idPasajero: idPasajero,
      idCliente: json['idCliente'] ?? 0,
      idTipoPasajero: json['idTipoPasajero']?.toString(),
    );
  }
}

class PassengerInfo {
  final int id;
  final String nombre;
  final String apellidoPaterno;
  final String apellidoMaterno;

  PassengerInfo({
    required this.id,
    required this.nombre,
    required this.apellidoPaterno,
    required this.apellidoMaterno,
  });

  String get nombreCompleto => '$nombre $apellidoPaterno $apellidoMaterno'.trim();

  factory PassengerInfo.fromJson(Map<String, dynamic> json) {
    return PassengerInfo(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      nombre: json['nombre'] ?? '',
      apellidoPaterno: json['apellidoPaterno'] ?? '',
      apellidoMaterno: json['apellidoMaterno'] ?? '',
    );
  }
}

final walletService = WalletService();

