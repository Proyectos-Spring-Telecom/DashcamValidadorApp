import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import '../utils/logger.dart';

// Importar logger para debugging

/// Modelo para la respuesta de ubicación GPS nativa
class NativeGpsLocationResponse {
  final double lat;
  final double lon;
  final double exactitud;
  final String clasificacionExactitud;
  final String resultado; // "A" o "V"
  final double velocidad;
  final double velocidadKmh;
  final double direccion;
  final int estado; // 1 = en movimiento, 0 = detenido
  final bool tieneVelocidad;
  final bool tieneDireccion;
  final int timestamp;
  final String provider;

  NativeGpsLocationResponse({
    required this.lat,
    required this.lon,
    required this.exactitud,
    required this.clasificacionExactitud,
    required this.resultado,
    required this.velocidad,
    required this.velocidadKmh,
    required this.direccion,
    required this.estado,
    required this.tieneVelocidad,
    required this.tieneDireccion,
    required this.timestamp,
    required this.provider,
  });

  factory NativeGpsLocationResponse.fromPosition(Position position) {
    // Manejar velocidad: si es -1 o negativa, usar 0
    // position.speed viene en m/s, puede ser -1 si no está disponible
    final velocidadMs = position.speed >= 0 ? position.speed : 0.0;
    final velocidadKmh = velocidadMs * 3.6;
    final exactitud = position.accuracy;
    
    // Manejar dirección: si es -1 o negativa, usar 0
    // position.heading viene en grados (0-360), puede ser -1 si no está disponible
    final direccion = position.heading >= 0 ? position.heading : 0.0;
    
    // Log para debugging de valores GPS
    if (position.speed < 0 || position.heading < 0) {
      appLogger.w('GPS: Valores no disponibles - speed: ${position.speed}, heading: ${position.heading}');
    }
    
    // Determinar clasificación de exactitud
    String clasificacionExactitud;
    if (exactitud <= 5) {
      clasificacionExactitud = 'Excelente';
    } else if (exactitud <= 10) {
      clasificacionExactitud = 'Buena';
    } else if (exactitud <= 20) {
      clasificacionExactitud = 'Regular';
    } else if (exactitud <= 50) {
      clasificacionExactitud = 'Mala';
    } else {
      clasificacionExactitud = 'Muy mala';
    }

    // Determinar si está en movimiento (velocidad > 1 km/h)
    final estado = velocidadKmh > 1.0 ? 1 : 0;
    
    // Determinar resultado basado en exactitud
    final resultado = exactitud < 1000 ? 'A' : 'V';

    return NativeGpsLocationResponse(
      lat: position.latitude,
      lon: position.longitude,
      exactitud: exactitud,
      clasificacionExactitud: clasificacionExactitud,
      resultado: resultado,
      velocidad: velocidadMs,
      velocidadKmh: velocidadKmh,
      direccion: direccion,
      estado: estado,
      tieneVelocidad: position.speed >= 0,
      tieneDireccion: position.heading >= 0,
      timestamp: position.timestamp.millisecondsSinceEpoch,
      provider: _getProviderName(position),
    );
  }

  static String _getProviderName(Position position) {
    // Geolocator no expone directamente el proveedor, inferido por precisión (solo uso interno)
    if (position.accuracy <= 10) {
      return 'gps';
    } else if (position.accuracy <= 100) {
      return 'network';
    } else {
      return 'baja'; // No mostrar "PASSIVE" en UI
    }
  }

  bool get isValid => resultado == 'A';
  bool get isMoving => estado == 1;
  
  /// Obtiene la dirección cardinal aproximada
  String get direccionCardinal {
    if (!tieneDireccion || direccion < 0) return 'Sin dirección';
    if (direccion >= 337.5 || direccion < 22.5) return 'Norte';
    if (direccion >= 22.5 && direccion < 67.5) return 'Noreste';
    if (direccion >= 67.5 && direccion < 112.5) return 'Este';
    if (direccion >= 112.5 && direccion < 157.5) return 'Sureste';
    if (direccion >= 157.5 && direccion < 202.5) return 'Sur';
    if (direccion >= 202.5 && direccion < 247.5) return 'Suroeste';
    if (direccion >= 247.5 && direccion < 292.5) return 'Oeste';
    return 'Noroeste';
  }

  /// Obtiene la calidad de la señal GPS basada en la exactitud
  String get calidadSenal {
    if (exactitud <= 5) return 'Excelente';
    if (exactitud <= 10) return 'Buena';
    if (exactitud <= 20) return 'Regular';
    return 'Pobre';
  }

  /// Obtiene el tiempo transcurrido desde la última actualización
  Duration get tiempoTranscurrido {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: now - timestamp);
  }

  /// Verifica si la ubicación es reciente (menos de 30 segundos)
  /// Aumentado para permitir envíos cada 3 minutos con datos válidos
  bool get esReciente {
    return tiempoTranscurrido.inSeconds < 30;
  }

  /// Verifica si la ubicación es confiable (válida + exactitud razonable)
  bool get esConfiable {
    return isValid && exactitud < 100; // Menos de 100 metros de error
  }

  /// Verifica si la ubicación es utilizable para navegación
  bool get esUtilizable {
    return isValid && exactitud < 500; // Menos de 500 metros de error
  }
}

/// Servicio para obtener ubicación GPS nativa usando geolocator
class NativeGpsService {
  StreamSubscription<Position>? _positionSubscription;
  final StreamController<NativeGpsLocationResponse> _locationController = 
      StreamController<NativeGpsLocationResponse>.broadcast();
  
  // Control de filtrado y estabilidad
  NativeGpsLocationResponse? _lastLocation;
  DateTime? _lastUpdateTime;
  // Sin restricción de intervalo mínimo - dispositivo dedicado, sin preocupación por batería
  static const double _maxJumpDistance = 1000; // Máximo salto de 1km (solo para outliers)

  /// Stream de ubicaciones GPS
  Stream<NativeGpsLocationResponse> get locationStream => _locationController.stream;

  /// Configuración optimizada para máxima frecuencia (dispositivo dedicado)
  /// Sin restricciones de batería o datos - actualizaciones máximas posibles
  static const LocationSettings _fastLocationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 0,
  );

  /// Verifica permisos de ubicación (no exige que el toggle GPS del sistema esté ON).
  Future<bool> _ensureLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    appLogger.d('Estado de permisos actual: $permission');

    if (permission == LocationPermission.denied) {
      appLogger.i('Solicitando permisos de ubicación...');
      permission = await Geolocator.requestPermission();
      appLogger.d('Resultado de solicitud de permisos: $permission');
    }

    if (permission == LocationPermission.deniedForever) {
      appLogger.e('❌ Los permisos de ubicación están permanentemente denegados');
      return false;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      return true;
    }

    appLogger.w('⚠️ Permisos de ubicación no concedidos: $permission');
    return false;
  }

  /// Verifica permisos y avisa si el servicio de ubicación parece apagado.
  Future<bool> _handleLocationPermission() async {
    if (!await _ensureLocationPermission()) {
      appLogger.e('❌ Los permisos de ubicación fueron denegados por el usuario');
      return false;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      appLogger.w(
        '⚠️ El sistema reporta ubicación apagada; se intentará obtener señal GPS igualmente.',
      );
    } else {
      appLogger.d('✅ Servicio de ubicación habilitado');
    }

    return true;
  }

  /// Obtiene la ubicación actual una sola vez con máxima precisión
  /// Fuerza la activación del sensor GPS para obtener una ubicación precisa
  Future<NativeGpsLocationResponse?> getCurrentLocation({bool highAccuracy = true}) async {
    try {
      appLogger.d('Obteniendo ubicación GPS actual...');
      
      // Verificar permisos y servicio
      if (!await _handleLocationPermission()) {
        appLogger.e('No se pueden obtener permisos o servicio de ubicación');
        return null;
      }

      // Usar máxima precisión para dispositivo dedicado
      // Esto fuerza la activación del sensor GPS físico
      appLogger.d('Solicitando ubicación con máxima precisión (esto activará el sensor GPS)...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 45),
      );

      if (position != null) {
        appLogger.i('✅ Ubicación GPS obtenida: Lat=${position.latitude}, Lon=${position.longitude}, Accuracy=${position.accuracy}m');
        return NativeGpsLocationResponse.fromPosition(position);
      } else {
        appLogger.w('No se pudo obtener ubicación GPS');
        return null;
      }
    } catch (e) {
      appLogger.e('Error al obtener ubicación actual', e);
      // Si es un timeout, puede ser que el GPS esté tardando en activarse
      if (e.toString().contains('timeout') || e.toString().contains('TimeoutException')) {
        appLogger.w('Timeout al obtener ubicación GPS - el sensor puede estar tardando en activarse');
      }
      return null;
    }
  }

  /// Fuerza la activación del sensor GPS obteniendo una ubicación inicial
  /// Esto es necesario para "despertar" el GPS antes de iniciar el stream
  Future<bool> _forceGpsActivation() async {
    try {
      appLogger.i('Forzando activación del sensor GPS...');
      
      // Obtener ubicación inicial con máxima precisión para activar el GPS
      // Esto fuerza al sistema a activar físicamente el sensor GPS
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );
      
      if (position != null) {
        appLogger.i('✅ Sensor GPS activado exitosamente');
        appLogger.d('Ubicación inicial: Lat=${position.latitude}, Lon=${position.longitude}, Accuracy=${position.accuracy}m');
        return true;
      }
      
      appLogger.w('No se pudo obtener ubicación inicial para activar GPS');
      return false;
    } catch (e) {
      appLogger.w('Error al forzar activación del GPS (puede ser normal si el GPS tarda en activarse): $e');
      // No fallar completamente, el stream puede funcionar sin esto
      return false;
    }
  }

  /// Inicia el stream de ubicaciones en tiempo real con filtrado inteligente
  /// IMPORTANTE: Fuerza la activación del sensor GPS antes de iniciar el stream
  Future<bool> startLocationStream({bool highAccuracy = true}) async {
    try {
      appLogger.i('Iniciando stream de ubicación GPS...');
      
      // Verificar permisos primero
      if (!await _handleLocationPermission()) {
        appLogger.e('Permisos de ubicación no concedidos');
        return false;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        appLogger.w(
          'Servicio de ubicación reportado como apagado; iniciando stream GPS de todos modos',
        );
      }

      // Cancelar stream anterior si existe
      await stopLocationStream();

      // PASO CRÍTICO: Forzar activación del sensor GPS antes de iniciar el stream
      // Esto asegura que el GPS físico se active y esté listo
      appLogger.i('Activando sensor GPS antes de iniciar stream...');
      final gpsActivated = await _forceGpsActivation();
      if (!gpsActivated) {
        appLogger.w('No se pudo activar GPS inicialmente, pero continuando con stream (puede tardar más)');
      }

      // Pequeño delay para asegurar que el GPS esté completamente activo
      await Future.delayed(const Duration(milliseconds: 500));

      // Iniciar stream con configuración optimizada para modo rápido
      appLogger.i('Iniciando stream de ubicación GPS...');
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: _fastLocationSettings,
      ).listen(
        (Position position) {
          _processLocationUpdate(position);
        },
        onError: (error) {
          appLogger.w('Error en stream de ubicación GPS', error);
          // No detener el stream por errores, solo loguear
        },
        cancelOnError: false, // No cancelar el stream en caso de error
      );
      
      appLogger.i('✅ Stream GPS iniciado correctamente con configuración máxima frecuencia');

      return true;
    } catch (e) {
      appLogger.e('Error al iniciar stream de ubicación', e);
      return false;
    }
  }

  /// Procesa actualizaciones de ubicación - máxima frecuencia sin restricciones
  /// Dispositivo dedicado: sin limitaciones de batería o datos
  void _processLocationUpdate(Position position) {
    final now = DateTime.now();
    
    final newLocation = NativeGpsLocationResponse.fromPosition(position);
    
    // Log de valores GPS para debugging
    appLogger.d('📍 GPS Update: speed=${position.speed}m/s (${newLocation.velocidadKmh.toStringAsFixed(2)}km/h), heading=${position.heading}°, estado=${newLocation.estado}');
    
    // Solo filtrar outliers extremos - permitir todas las actualizaciones válidas
    // Filtro 1: Detectar saltos grandes (outliers) - solo para errores obvios
    if (_lastLocation != null) {
      final distance = _calculateDistance(
        _lastLocation!.lat, _lastLocation!.lon,
        newLocation.lat, newLocation.lon,
      );
      
      if (distance > _maxJumpDistance) {
        appLogger.w('Salto grande detectado en GPS (${distance.toStringAsFixed(0)}m), descartando outlier');
        return;
      }
    }
    
    // Filtro 2: Verificar que no sea muy antigua (solo datos obsoletos)
    if (!newLocation.esReciente) {
      appLogger.w('Ubicación GPS antigua descartada (${newLocation.tiempoTranscurrido.inSeconds}s)');
      return;
    }
    
    // Sin restricción de frecuencia - aceptar todas las actualizaciones válidas
    // El dispositivo está dedicado para operación, sin preocupación por batería
    
    // Ubicación válida - enviar al stream inmediatamente
    _lastLocation = newLocation;
    _lastUpdateTime = now;
    _locationController.add(newLocation);
  }
  
  /// Calcula distancia entre dos puntos en metros usando fórmula de Haversine
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371000; // Radio de la Tierra en metros
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLon = (lon2 - lon1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) *
        sin(dLon / 2) * sin(dLon / 2);
    final double c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  /// Detiene el stream de ubicaciones
  Future<void> stopLocationStream() async {
    if (_positionSubscription != null) {
      appLogger.i('Deteniendo stream de ubicación GPS');
      await _positionSubscription?.cancel();
      _positionSubscription = null;
    }
    // No limpiar _lastLocation y _lastUpdateTime para mantener el estado
    // Esto ayuda a mantener continuidad cuando se reinicia
  }

  /// Verifica si los servicios de ubicación están disponibles
  /// Retorna true si el servicio está habilitado, false en caso contrario
  Future<bool> isLocationServiceEnabled() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      appLogger.w('⚠️ Servicio de ubicación deshabilitado en el dispositivo');
    } else {
      appLogger.d('✅ Servicio de ubicación habilitado');
    }
    return enabled;
  }

  /// Verifica el estado completo del GPS (permisos + servicio)
  /// Útil para diagnóstico antes de intentar activar el GPS
  Future<Map<String, dynamic>> checkGpsStatus() async {
    final status = <String, dynamic>{};
    
    // Verificar servicio de ubicación
    status['serviceEnabled'] = await Geolocator.isLocationServiceEnabled();
    
    // Verificar permisos
    final permission = await Geolocator.checkPermission();
    status['permission'] = permission.toString();
    status['hasPermission'] = permission == LocationPermission.whileInUse || 
                               permission == LocationPermission.always;
    
    // Verificar si puede obtener ubicación
    status['canGetLocation'] = status['hasPermission'] == true;
    
    appLogger.d('Estado GPS: $status');
    return status;
  }

  /// Obtiene el estado actual de los permisos
  Future<LocationPermission> getPermissionStatus() async {
    return await Geolocator.checkPermission();
  }

  /// Abre la configuración de ubicación del dispositivo
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  /// Abre la configuración de la aplicación
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }

  /// Libera recursos
  void dispose() {
    stopLocationStream();
    _locationController.close();
  }
}

/// Instancia global del servicio GPS nativo
final nativeGpsService = NativeGpsService();
