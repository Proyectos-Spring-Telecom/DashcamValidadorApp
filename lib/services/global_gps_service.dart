import 'dart:async';
import 'package:flutter/foundation.dart';
import 'native_gps_service.dart';
import 'position_service.dart';
import '../utils/logger.dart';

/// Servicio GPS global que maneja una sola instancia del GPS
/// para toda la aplicación, evitando conflictos entre vistas
class GlobalGpsService extends ChangeNotifier {
  static final GlobalGpsService _instance = GlobalGpsService._internal();
  factory GlobalGpsService() => _instance;
  GlobalGpsService._internal();

  // Estado del GPS
  NativeGpsLocationResponse? _currentLocation;
  bool _isActive = false;
  bool _isLoadingLocation = false;
  String? _errorMessage;
  int _updateCount = 0;
  DateTime? _lastUpdateTime;
  
  // Modo persistente: GPS se mantiene activo permanentemente después del login
  // No se detiene aunque no haya listeners activos
  bool _persistentMode = false;
  
  // Listeners activos
  final Set<String> _activeListeners = {};
  StreamSubscription<NativeGpsLocationResponse>? _gpsSubscription;
  
  // Sistema de monitoreo de salud del GPS
  Timer? _healthCheckTimer;
  GpsHealthStatus _healthStatus = GpsHealthStatus.unknown;
  DateTime? _lastHealthCheckTime;
  static const Duration _healthCheckInterval = Duration(seconds: 30); // Verificar cada 30 segundos
  static const Duration _maxTimeWithoutUpdate = Duration(seconds: 120);
  static const Duration _degradedThreshold = Duration(seconds: 30); // Degradado después de 30 segundos

  // Getters públicos
  NativeGpsLocationResponse? get currentLocation => _currentLocation;
  bool get isActive => _isActive;
  bool get isLoadingLocation => _isLoadingLocation;
  String? get errorMessage => _errorMessage;
  int get updateCount => _updateCount;
  DateTime? get lastUpdateTime => _lastUpdateTime;
  bool get hasActiveListeners => _activeListeners.isNotEmpty;
  GpsHealthStatus get healthStatus => _healthStatus;
  DateTime? get lastHealthCheckTime => _lastHealthCheckTime;

  /// Registra un listener activo (por ejemplo, una vista que necesita GPS)
  Future<void> registerListener(String listenerId) async {
    appLogger.d('Registrando listener GPS: $listenerId');
    _activeListeners.add(listenerId);
    
    // Si es el primer listener o el GPS no está activo, iniciar GPS
    // En modo persistente, el GPS ya debería estar activo, pero verificamos
    if (_activeListeners.length == 1 || !_isActive) {
      await _startGpsService();
    } else {
      appLogger.d('GPS ya activo (modo persistente o con otros listeners), no reiniciando');
    }
    
    // Diferir la notificación para evitar setState durante build
    Future.microtask(() => notifyListeners());
  }

  /// Desregistra un listener
  Future<void> unregisterListener(String listenerId) async {
    appLogger.d('Desregistrando listener GPS: $listenerId');
    _activeListeners.remove(listenerId);
    
    // Si no quedan listeners Y no está en modo persistente, detener GPS
    // En modo persistente, el GPS se mantiene activo independientemente de los listeners
    if (_activeListeners.isEmpty && !_persistentMode) {
      await _stopGpsService();
    } else if (_persistentMode) {
      appLogger.d('GPS en modo persistente, manteniendo activo sin listeners');
    }
    
    // Diferir la notificación para evitar setState durante build
    Future.microtask(() => notifyListeners());
  }

  /// Inicia el servicio GPS
  /// Evita reiniciar si ya está activo para mantener la señal satelital
  Future<void> _startGpsService() async {
    // Si el GPS ya está activo y tiene una suscripción válida, no reiniciar
    // Esto evita perder la señal satelital (cold start tarda mucho)
    if (_isActive && _gpsSubscription != null) {
      appLogger.d('Servicio GPS ya activo con suscripción válida, manteniendo activo');
      // Verificar que el stream sigue funcionando
      if (_currentLocation != null && _currentLocation!.esReciente) {
        appLogger.d('GPS funcionando correctamente, no es necesario reiniciar');
        return;
      } else {
        appLogger.w('GPS activo pero sin datos recientes, verificando stream...');
        // Si no hay datos recientes, puede haber un problema, pero no reiniciar todavía
        // Intentar obtener ubicación actual sin reiniciar
        try {
          final currentLocation = await nativeGpsService.getCurrentLocation();
          if (currentLocation != null && currentLocation.esReciente) {
            appLogger.d('GPS recuperado sin reiniciar');
            _handleLocationUpdate(currentLocation);
            return;
          }
        } catch (e) {
          appLogger.w('Error al verificar GPS, puede ser necesario reiniciar: $e');
        }
        // Solo si realmente hay un problema, reiniciar
        appLogger.w('GPS no responde correctamente, reiniciando...');
        await _stopGpsService();
      }
    }

    appLogger.i('Iniciando servicio GPS (modo rápido)');
    _isLoadingLocation = true;
    _errorMessage = null;
    // Diferir la notificación para evitar setState durante build
    Future.microtask(() => notifyListeners());

    try {
      // Verificar estado completo del GPS antes de iniciar
      appLogger.i('Verificando estado del GPS antes de iniciar...');
      final gpsStatus = await nativeGpsService.checkGpsStatus();
      
      if (!gpsStatus['hasPermission'] as bool) {
        _setError('Permisos de ubicación no concedidos. Concede permisos a la aplicación.');
        appLogger.e('❌ No se puede iniciar GPS: permisos de ubicación no concedidos');
        return;
      }

      if (!gpsStatus['serviceEnabled'] as bool) {
        appLogger.w('⚠️ Ubicación del sistema apagada; se intentará activar el GPS igualmente');
      }
      
      appLogger.i('✅ Permisos GPS verificados, iniciando servicio');

      // Obtener ubicación inicial para activar el sensor GPS
      appLogger.i('Obteniendo ubicación inicial para activar sensor GPS...');
      final initialLocation = await nativeGpsService.getCurrentLocation();
      if (initialLocation != null) {
        appLogger.i('✅ Ubicación inicial GPS obtenida - sensor GPS activado');
        _handleLocationUpdate(initialLocation);
      } else {
        appLogger.w('⚠️ No se pudo obtener ubicación inicial, pero continuando con stream...');
      }

      // Iniciar stream de ubicaciones (esto también fuerza la activación del GPS)
      appLogger.i('Iniciando stream de ubicación GPS...');
      final streamStarted = await nativeGpsService.startLocationStream(highAccuracy: true);
      if (streamStarted) {
        // Cancelar suscripción anterior si existe
        await _gpsSubscription?.cancel();
        
        _gpsSubscription = nativeGpsService.locationStream.listen(
          _handleLocationUpdate,
          onError: (error) {
            appLogger.w('Error en stream GPS', error);
            // Actualizar estado de salud cuando hay errores
            _healthStatus = GpsHealthStatus.degraded;
            _errorMessage = 'Error en stream GPS: $error';
            notifyListeners();
            // No establecer error permanente, solo loguear
            // El stream puede recuperarse automáticamente
          },
          cancelOnError: false, // No cancelar el stream en caso de error
        );
        _isActive = true;
        _healthStatus = GpsHealthStatus.unknown; // Resetear estado de salud
        appLogger.i('Servicio GPS iniciado correctamente (máxima frecuencia)');
        
        // Iniciar el servicio de envío de posiciones al backend
        positionService.start();
        
        // Iniciar monitoreo de salud del GPS
        _startHealthCheck();
      } else {
        _setError('No se pudo iniciar GPS');
      }
    } catch (e) {
      appLogger.e('Error al iniciar GPS', e);
      _setError('Error al inicializar GPS: $e');
    }

    _isLoadingLocation = false;
    notifyListeners();
  }

  /// Detiene el servicio GPS
  /// IMPORTANTE: En modo persistente, no se detiene automáticamente para mantener la señal satelital
  Future<void> _stopGpsService({bool force = false}) async {
    if (!_isActive) {
      appLogger.d('Servicio GPS ya inactivo, ignorando');
      return;
    }

    // En modo persistente, no detener el GPS automáticamente
    // Solo detener si se fuerza explícitamente (desde stopPersistent)
    if (_persistentMode && !force) {
      appLogger.w('Intento de detener GPS en modo persistente - ignorando para mantener señal satelital');
      return;
    }

    appLogger.i('Deteniendo servicio GPS${force ? " (forzado)" : ""}');
    
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    await nativeGpsService.stopLocationStream();
    
    _isActive = false;
    _isLoadingLocation = false;
    _healthStatus = GpsHealthStatus.disconnected;
    // NO resetear _updateCount y _lastUpdateTime para mantener el estado
    // Esto permite ver el historial incluso después de detener
    
    // Detener monitoreo de salud
    _stopHealthCheck();
    
    // Detener el servicio de envío de posiciones
    positionService.stop();
    
    appLogger.i('Servicio GPS detenido correctamente');
    notifyListeners();
  }

  /// Maneja las actualizaciones de ubicación
  void _handleLocationUpdate(NativeGpsLocationResponse location) {
    final now = DateTime.now();
    String frequencyInfo = '';
    
    if (_lastUpdateTime != null) {
      final timeDiff = now.difference(_lastUpdateTime!).inMilliseconds;
      frequencyInfo = ' (${timeDiff}ms desde última)';
    }
    
    _lastUpdateTime = now;
    _updateCount++;

    appLogger.d('GPS Update #$_updateCount: Lat=${location.lat}, Lon=${location.lon}, Accuracy=${location.exactitud}m$frequencyInfo');

    _currentLocation = location;
    _errorMessage = null;
    
    // Determinar mensaje de error si la ubicación no es válida
    if (!location.isValid || location.exactitud > 500) {
      if (!location.esReciente) {
        _errorMessage = 'GPS desactualizado';
      } else if (!location.isValid) {
        _errorMessage = 'Señal GPS inválida (${location.resultado})';
      } else if (location.exactitud > 500) {
        _errorMessage = 'GPS con muy baja precisión (±${location.exactitud.toStringAsFixed(0)}m)';
      }
    }

    // Actualizar estado de salud basado en la actualización recibida
    _updateHealthStatus();

    notifyListeners();
  }
  
  /// Actualiza el estado de salud del GPS basado en las actualizaciones recibidas
  void _updateHealthStatus() {
    final now = DateTime.now();
    final previousStatus = _healthStatus;
    
    if (!_isActive) {
      _healthStatus = GpsHealthStatus.disconnected;
      _stopHealthCheck();
      if (previousStatus != _healthStatus) {
        appLogger.w('Estado de salud GPS: Desconectado');
      }
      return;
    }
    
    if (_lastUpdateTime == null) {
      _healthStatus = GpsHealthStatus.unknown;
      return;
    }
    
    final timeSinceLastUpdate = now.difference(_lastUpdateTime!);
    final location = _currentLocation;
    
    // Evaluar salud basado en tiempo desde última actualización y calidad de señal
    if (timeSinceLastUpdate > _maxTimeWithoutUpdate) {
      _healthStatus = GpsHealthStatus.unhealthy;
      _errorMessage = 'GPS sin actualizaciones por ${timeSinceLastUpdate.inSeconds}s';
      appLogger.w('Estado de salud GPS: No saludable - sin actualizaciones por ${timeSinceLastUpdate.inSeconds}s');
    } else if (timeSinceLastUpdate > _degradedThreshold) {
      _healthStatus = GpsHealthStatus.degraded;
      if (_errorMessage == null) {
        _errorMessage = 'GPS con actualizaciones lentas';
      }
      if (previousStatus != _healthStatus) {
        appLogger.w('Estado de salud GPS: Degradado - actualizaciones cada ${timeSinceLastUpdate.inSeconds}s');
      }
    } else if (location != null && location.isValid && location.exactitud < 100) {
      _healthStatus = GpsHealthStatus.healthy;
      if (previousStatus != _healthStatus && previousStatus != GpsHealthStatus.unknown) {
        appLogger.i('Estado de salud GPS: Saludable - actualizaciones regulares');
      }
    } else if (location != null && location.isValid) {
      _healthStatus = GpsHealthStatus.degraded;
      if (previousStatus != _healthStatus) {
        appLogger.w('Estado de salud GPS: Degradado - baja precisión (${location.exactitud.toStringAsFixed(0)}m)');
      }
    } else {
      _healthStatus = GpsHealthStatus.degraded;
    }
    
    _lastHealthCheckTime = now;
  }
  
  /// Inicia el monitoreo periódico de salud del GPS
  void _startHealthCheck() {
    _stopHealthCheck(); // Asegurar que no hay múltiples timers
    
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      if (!_isActive) {
        _stopHealthCheck();
        return;
      }
      
      _updateHealthStatus();
      
      // Si el GPS está en modo persistente y no saludable, intentar recuperación
      if (_persistentMode && _healthStatus == GpsHealthStatus.unhealthy) {
        appLogger.w('GPS en modo persistente pero no saludable, intentando recuperación...');
        _attemptRecovery();
      }
    });
    
    appLogger.d('Monitoreo de salud GPS iniciado (verificación cada ${_healthCheckInterval.inSeconds}s)');
  }
  
  /// Detiene el monitoreo de salud del GPS
  void _stopHealthCheck() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = null;
  }
  
  /// Intenta recuperar el GPS si está en estado no saludable
  Future<void> _attemptRecovery() async {
    if (!_persistentMode || !_isActive) return;
    
    appLogger.i('Intentando recuperar conexión GPS...');
    
    try {
      // Intentar obtener ubicación actual para verificar si el GPS responde
      final location = await nativeGpsService.getCurrentLocation();
      if (location != null && location.esReciente) {
        appLogger.i('GPS recuperado exitosamente');
        _handleLocationUpdate(location);
      } else {
        appLogger.w('GPS no responde correctamente, puede requerir reinicio manual');
      }
    } catch (e) {
      appLogger.e('Error al intentar recuperar GPS', e);
    }
  }

  /// Establece un mensaje de error
  void _setError(String error) {
    _errorMessage = error;
    _isLoadingLocation = false;
    notifyListeners();
  }

  /// Fuerza una actualización de ubicación
  Future<void> forceLocationUpdate() async {
    if (!_isActive) return;
    
    appLogger.d('Forzando actualización de ubicación GPS');
    final location = await nativeGpsService.getCurrentLocation();
    if (location != null) {
      _handleLocationUpdate(location);
    }
  }

  /// Inicia el GPS en modo persistente (permanece activo después del login)
  /// El GPS se mantendrá activo en primer y segundo plano independientemente de las vistas
  /// CRÍTICO: No reinicia el GPS si ya está activo para mantener la señal satelital
  Future<void> startPersistent() async {
    if (_persistentMode) {
      appLogger.d('GPS ya está en modo persistente');
      // Verificar que el GPS sigue activo
      if (!_isActive) {
        appLogger.w('⚠️ Modo persistente activo pero GPS inactivo, reactivando...');
        await _startGpsService();
      } else {
        appLogger.d('✅ GPS en modo persistente y activo');
      }
      return;
    }
    
    appLogger.i('🔄 Activando modo persistente GPS - se mantendrá activo permanentemente');
    _persistentMode = true;
    
    // Verificar estado del GPS antes de iniciar
    appLogger.i('Verificando estado del GPS antes de activar modo persistente...');
    final gpsStatus = await nativeGpsService.checkGpsStatus();
    
    if (!gpsStatus['hasPermission'] as bool) {
      appLogger.e('❌ No se puede activar GPS en modo persistente: permisos no concedidos');
      _setError('No se puede activar GPS. Concede permisos de ubicación a la aplicación.');
      return;
    }

    if (!gpsStatus['serviceEnabled'] as bool) {
      appLogger.w('⚠️ Ubicación del sistema apagada; se intentará obtener señal GPS');
      _errorMessage = 'Activa la ubicación en Ajustes para mejor señal GPS';
    }
    
    // Si el GPS no está activo, iniciarlo
    // Si ya está activo, NO reiniciarlo para mantener la señal satelital
    if (!_isActive) {
      appLogger.i('🚀 Iniciando GPS en modo persistente (esto activará el sensor GPS físico)...');
      await _startGpsService();
    } else {
      appLogger.i('✅ GPS ya está activo, activando modo persistente sin reiniciar (manteniendo señal satelital)');
      // Asegurar que el servicio de posiciones esté corriendo
      if (!positionService.isRunning) {
        positionService.start();
      }
    }
    
    notifyListeners();
  }

  /// Detiene el modo persistente del GPS
  /// El GPS se detendrá si no hay listeners activos
  Future<void> stopPersistent() async {
    if (!_persistentMode) {
      appLogger.d('GPS no está en modo persistente');
      return;
    }
    
    appLogger.i('Desactivando modo persistente GPS');
    _persistentMode = false;
    
    // Ahora sí podemos detener el GPS si no hay listeners activos
    // Usar force=true para permitir la detención
    if (_activeListeners.isEmpty) {
      appLogger.i('No hay listeners activos, deteniendo GPS después de desactivar modo persistente');
      await _stopGpsService(force: true);
    } else {
      appLogger.d('Hay ${_activeListeners.length} listeners activos, GPS se mantendrá activo');
    }
    
    notifyListeners();
  }

  /// Verifica si el GPS está en modo persistente
  bool get isPersistent => _persistentMode;

  /// Limpia todos los recursos
  @override
  void dispose() {
    appLogger.i('Limpiando recursos GPS');
    _stopHealthCheck();
    _stopGpsService();
    _activeListeners.clear();
    super.dispose();
  }
}

/// Estados de salud del GPS
enum GpsHealthStatus {
  unknown,      // Estado desconocido (inicial)
  healthy,      // GPS funcionando correctamente con actualizaciones regulares
  degraded,     // GPS funcionando pero con problemas (baja precisión, actualizaciones lentas)
  unhealthy,    // GPS no responde o sin actualizaciones por mucho tiempo
  disconnected, // GPS desconectado o inactivo
}

/// Instancia global del servicio GPS
final globalGpsService = GlobalGpsService();
