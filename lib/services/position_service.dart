import 'dart:async';
import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../services/device_api_service.dart';
import '../services/storage_service.dart';
import '../services/global_gps_service.dart';
import '../services/native_gps_service.dart';
import '../utils/logger.dart';
import '../config/app_config.dart';

/// Servicio para enviar posiciones GPS al backend
/// Se ejecuta automáticamente cada 3 minutos cuando hay GPS activo
class PositionService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;
  final GlobalGpsService _gpsService = globalGpsService;
  final StorageService _storage = StorageService();

  Timer? _positionTimer;
  bool _isRunning = false;

  /// Inicia el servicio de envío de posiciones
  /// Solo se activa si hay GPS activo y válido
  void start() {
    if (_isRunning) {
      appLogger.w('PositionService ya está en ejecución');
      return;
    }

    appLogger.i('Iniciando PositionService - Enviará posiciones cada 3 minutos');
    _isRunning = true;

    // Intentar enviar posición inicial si hay GPS válido (después de un pequeño delay)
    Future.delayed(AppConfig.positionInitialDelay, () {
      if (_isRunning) {
        _checkAndSendPosition();
      }
    });

    // Configurar timer para enviar cada 3 minutos
    _positionTimer = Timer.periodic(AppConfig.positionSendInterval, (_) {
      _checkAndSendPosition();
    });
  }

  /// Detiene el servicio de envío de posiciones
  void stop() {
    if (!_isRunning) {
      return;
    }

    appLogger.i('Deteniendo PositionService');
    _isRunning = false;
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  /// Verifica si hay GPS válido y envía la posición
  Future<void> _checkAndSendPosition() async {
    if (!_isRunning) return;

    final location = _gpsService.currentLocation;
    final isActive = _gpsService.isActive;

    // Solo enviar si hay GPS activo y válido
    if (!isActive || location == null || !location.isValid) {
      appLogger.d('GPS no disponible o inválido, omitiendo envío de posición');
      return;
    }

    // Verificar que la exactitud sea razonable (menos de 500m)
    if (location.exactitud > AppConfig.maxGpsAccuracy) {
      appLogger.w('GPS con baja exactitud (${location.exactitud}m), omitiendo envío');
      return;
    }

    // Verificar que la ubicación sea reciente (menos de 30 segundos)
    // Para asegurar que no estamos enviando datos obsoletos
    if (!location.esReciente && location.tiempoTranscurrido.inSeconds > 30) {
      appLogger.w('GPS desactualizado (${location.tiempoTranscurrido.inSeconds}s), omitiendo envío');
      return;
    }

    await _sendPosition(location);
  }

  /// Mismo origen que [WalletService.debitTripTransaction]: storage → dispositivo local.
  Future<String?> _resolveNumeroSerieValidador() async {
    String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
    if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
      numeroSerieValidador = await deviceApiService.getValidadorSerie();
      if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
        await _storage.saveNumeroSerieValidador(numeroSerieValidador);
      }
    }
    return numeroSerieValidador;
  }

  static String _formatUtcDateTime(DateTime utc) {
    final t = utc.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}T'
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
  }

  /// Envía la posición GPS al backend
  Future<void> _sendPosition(NativeGpsLocationResponse location) async {
    try {
      appLogger.i('Enviando posición GPS al backend');

      final numeroSerieValidador = await _resolveNumeroSerieValidador();
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.w(
          'No se pudo obtener numeroSerieValidador, omitiendo envío de posición',
        );
        return;
      }

      final fechaHoraUtc =
          DateTime.fromMillisecondsSinceEpoch(location.timestamp, isUtc: true);
      final fechaHora = _formatUtcDateTime(fechaHoraUtc);

      final velocidad = location.velocidadKmh >= 0 ? location.velocidadKmh : 0.0;
      final direccion = location.direccion >= 0 ? location.direccion : 0.0;
      final latitud = double.parse(location.lat.toStringAsFixed(6));
      final longitud = double.parse(location.lon.toStringAsFixed(6));

      final requestData = {
        'exactitud': location.resultado,
        'estado': location.estado,
        'velocidad': double.parse(velocidad.toStringAsFixed(2)),
        'direccion': double.parse(direccion.toStringAsFixed(2)),
        'latitud': latitud,
        'longitud': longitud,
        'fechaHora': fechaHora,
        'numeroSerieValidador': numeroSerieValidador,
      };

      appLogger.i('📤 POST ${AppConfig.endpointPositions}');
      appLogger.i('   - exactitud: ${location.resultado}');
      appLogger.i('   - estado: ${location.estado}');
      appLogger.i('   - velocidad: ${requestData['velocidad']} km/h');
      appLogger.i('   - direccion: ${requestData['direccion']}°');
      appLogger.i('   - latitud: $latitud, longitud: $longitud');
      appLogger.i('   - fechaHora: $fechaHora');
      appLogger.i('   - numeroSerieValidador: $numeroSerieValidador');
      appLogger.d('Body: $requestData');

      final response = await _httpService.dio.post(
        AppConfig.endpointPositions,
        data: requestData,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('Posición GPS enviada exitosamente');
      } else {
        appLogger.w('Respuesta inesperada al enviar posición: ${response.statusCode}');
      }
    } on DioException catch (e) {
      final errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error al enviar posición GPS: $errorMessage', e);
      // No lanzar excepción, solo loguear el error
      // El servicio continuará intentando en el siguiente intervalo
    } catch (e) {
      appLogger.e('Error inesperado al enviar posición GPS', e);
    }
  }

  /// Fuerza el envío inmediato de la posición actual
  /// Útil para testing o envíos manuales
  Future<bool> sendCurrentPosition() async {
    final location = _gpsService.currentLocation;
    if (location == null || !location.isValid) {
      appLogger.w('No hay posición GPS válida para enviar');
      return false;
    }

    await _sendPosition(location);
    return true;
  }

  /// Verifica si el servicio está en ejecución
  bool get isRunning => _isRunning;
}

/// Instancia global del servicio de posiciones
final positionService = PositionService();

