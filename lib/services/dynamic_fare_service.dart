import 'package:flutter/foundation.dart';
import '../models/dynamic_fare_trip.dart';
import '../services/global_gps_service.dart';
import '../services/native_gps_service.dart';
import '../services/wallet_service.dart';
import '../utils/logger.dart';

/// Servicio para manejar los viajes de tarifa dinámica
/// Ahora también acumula distancia en tiempo real durante el trayecto
/// IMPORTANTE: Escucha globalGpsService en lugar de suscribirse directamente al stream nativo
/// para evitar conflictos con múltiples suscripciones al mismo stream
class DynamicFareService extends ChangeNotifier {
  // Mapa de viajes activos por número de serie del monedero
  final Map<String, DynamicFareTrip> _activeTrips = {};
  
  // Listener del globalGpsService para recibir actualizaciones GPS
  // Usamos addListener en lugar de suscribirnos directamente al stream para evitar conflictos
  bool _isListeningToGps = false;

  /// Obtiene todos los viajes activos
  Map<String, DynamicFareTrip> get activeTrips => Map.unmodifiable(_activeTrips);

  /// Obtiene todos los viajes (activos y completados)
  List<DynamicFareTrip> get allTrips => _activeTrips.values.toList();

  /// Inicia un viaje para un monedero
  /// Retorna true si se inició correctamente, false si ya existe un viaje activo
  Future<bool> startTrip(String numeroSerieMonedero) async {
    // Verificar si ya existe un viaje activo para este monedero
    if (_activeTrips.containsKey(numeroSerieMonedero)) {
      appLogger.w('Ya existe un viaje activo para el monedero: $numeroSerieMonedero');
      return false;
    }

    // Obtener coordenadas GPS actuales con timeout
    double lat = 0.0;
    double lon = 0.0;

    final location = globalGpsService.currentLocation;
    if (location != null && location.isValid) {
      lat = location.lat;
      lon = location.lon;
      appLogger.d('📍 Coordenadas iniciales desde globalGpsService: lat=$lat, lon=$lon');
    } else {
      appLogger.d('No hay ubicación en globalGpsService, obteniendo ubicación actual...');
      try {
        final fallback = await nativeGpsService.getCurrentLocation()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          appLogger.w('⚠️ Timeout al obtener ubicación GPS inicial');
          return null;
        });
        if (fallback != null && fallback.isValid) {
          lat = fallback.lat;
          lon = fallback.lon;
          appLogger.d('📍 Coordenadas iniciales desde getCurrentLocation: lat=$lat, lon=$lon');
        }
      } catch (e) {
        appLogger.w('⚠️ Error al obtener ubicación GPS inicial: $e');
      }
    }

    if (lat == 0.0 && lon == 0.0) {
      appLogger.w('⚠️ No se pudo obtener ubicación GPS para iniciar el viaje, usando 0.0, 0.0');
      // Aún así permitimos iniciar el viaje con coordenadas 0.0
    } else {
      appLogger.i('✅ Coordenadas iniciales obtenidas: lat=$lat, lon=$lon');
    }

    // Crear transacción de débito en el backend (inicio de viaje)
    // Usar monto inicial de 10 (se actualizará al finalizar con el monto real)
    final transactionId = await walletService.startTripDebit(
      amount: 10.0, // Monto inicial, se actualizará al finalizar
      lat: lat,
      lon: lon,
      numeroSerieMonedero: numeroSerieMonedero,
    );

    if (transactionId == null) {
      appLogger.e('❌ No se pudo crear la transacción de inicio en el backend');
      return false;
    }

    final trip = DynamicFareTrip(
      numeroSerieMonedero: numeroSerieMonedero,
      startTime: DateTime.now(),
      startLat: lat,
      startLon: lon,
      idTransaccionDebito: transactionId,
    );

    _activeTrips[numeroSerieMonedero] = trip;
    
    // Iniciar escucha del GPS si no está activa (solo una suscripción para todos los viajes)
    _startListeningToGps();
    
    appLogger.i('✅ Viaje iniciado para monedero: $numeroSerieMonedero en (${lat.toStringAsFixed(6)}, ${lon.toStringAsFixed(6)})');
    appLogger.i('✅ Transacción de inicio creada con ID: $transactionId');
    appLogger.i('📡 Escuchando actualizaciones GPS desde globalGpsService para calcular distancia recorrida');
    notifyListeners();
    return true;
  }

  /// Inicia la escucha del GPS global usando addListener en globalGpsService
  /// Esto evita múltiples suscripciones al mismo stream que pueden causar conflictos
  void _startListeningToGps() {
    // Si ya estamos escuchando, no hacer nada
    if (_isListeningToGps) {
      appLogger.d('Ya estamos escuchando actualizaciones GPS');
      return;
    }

    appLogger.i('Iniciando escucha de actualizaciones GPS desde globalGpsService');
    
    // Asegurar que el GPS esté activo
    if (!globalGpsService.isActive && !globalGpsService.isPersistent) {
      appLogger.w('GPS no está activo, activando modo persistente...');
      globalGpsService.startPersistent().catchError((e) {
        appLogger.e('Error al activar GPS: $e');
      });
    }

    // Escuchar cambios en globalGpsService usando addListener
    // Cuando globalGpsService notifica cambios, procesamos la ubicación actual
    globalGpsService.addListener(_onGpsServiceUpdate);
    
    _isListeningToGps = true;
    appLogger.i('✅ Escuchando actualizaciones GPS - ${_activeTrips.length} viaje(s) activo(s)');
  }

  /// Callback cuando globalGpsService se actualiza
  void _onGpsServiceUpdate() {
    final location = globalGpsService.currentLocation;
    if (location != null) {
      _processGpsUpdate(location);
    }
  }

  /// Procesa una actualización GPS y la distribuye a todos los viajes activos
  void _processGpsUpdate(NativeGpsLocationResponse location) {
    // Solo procesar si hay viajes activos
    if (_activeTrips.isEmpty) {
      return;
    }

    // Solo procesar ubicaciones válidas y con buena precisión
    if (!location.isValid || location.exactitud > 500) {
      appLogger.d('Ubicación GPS no válida o con baja precisión, omitiendo: accuracy=${location.exactitud}m');
      return;
    }

    // Distribuir la actualización a todos los viajes activos
    bool hasUpdates = false;
    for (final entry in _activeTrips.entries) {
      final monedero = entry.key;
      final trip = entry.value;
      
      // Solo actualizar si el viaje está activo
      if (trip.isActive) {
        final previousDistance = trip.accumulatedDistance;
        trip.updateLocation(location);
        final newDistance = trip.accumulatedDistance;
        
        // Log solo si hay cambio significativo en la distancia
        if (newDistance > previousDistance + 1.0) {
          hasUpdates = true;
          appLogger.d('📍 GPS Update para $monedero: distancia acumulada=${newDistance.toStringAsFixed(2)}m (+${(newDistance - previousDistance).toStringAsFixed(2)}m)');
        }
      }
    }

    // Notificar cambios solo si hubo actualizaciones significativas
    if (hasUpdates) {
      notifyListeners();
    }
  }

  /// Detiene la escucha del GPS cuando no hay viajes activos
  void _stopListeningToGps() {
    if (!_isListeningToGps) {
      return;
    }

    appLogger.i('Deteniendo escucha de actualizaciones GPS (no hay viajes activos)');
    globalGpsService.removeListener(_onGpsServiceUpdate);
    _isListeningToGps = false;
  }

  /// Finaliza un viaje para un monedero
  /// Retorna el viaje completado o null si no existe un viaje activo
  Future<DynamicFareTrip?> endTrip(String numeroSerieMonedero) async {
    final trip = _activeTrips[numeroSerieMonedero];
    if (trip == null) {
      appLogger.w('No existe un viaje activo para el monedero: $numeroSerieMonedero');
      return null;
    }

    // Obtener coordenadas GPS finales con timeout
    double lat = 0.0;
    double lon = 0.0;

    final location = globalGpsService.currentLocation;
    if (location != null && location.isValid) {
      lat = location.lat;
      lon = location.lon;
      appLogger.d('📍 Coordenadas finales desde globalGpsService: lat=$lat, lon=$lon');
    } else {
      appLogger.d('No hay ubicación en globalGpsService, obteniendo ubicación actual...');
      try {
        final fallback = await nativeGpsService.getCurrentLocation()
            .timeout(const Duration(seconds: 5), onTimeout: () {
          appLogger.w('⚠️ Timeout al obtener ubicación GPS final');
          return null;
        });
        if (fallback != null && fallback.isValid) {
          lat = fallback.lat;
          lon = fallback.lon;
          appLogger.d('📍 Coordenadas finales desde getCurrentLocation: lat=$lat, lon=$lon');
        }
      } catch (e) {
        appLogger.w('⚠️ Error al obtener ubicación GPS final: $e');
      }
    }

    if (lat == 0.0 && lon == 0.0) {
      appLogger.w('⚠️ No se pudo obtener ubicación GPS para finalizar el viaje, usando coordenadas de inicio');
      lat = trip.startLat;
      lon = trip.startLon;
    } else {
      appLogger.i('✅ Coordenadas finales obtenidas: lat=$lat, lon=$lon');
    }

    // Finalizar el viaje (la distancia ya está acumulada durante el trayecto)
    trip.completeTrip(lat, lon);
    
    appLogger.i('📏 Distancia total recorrida: ${trip.distance!.toStringAsFixed(2)} metros');
    appLogger.i('   - Puntos GPS registrados: ${trip.gpsPointCount}');
    appLogger.i('   - Distancia acumulada: ${trip.accumulatedDistance.toStringAsFixed(2)}m');
    appLogger.i('💰 Tarifa calculada: \$${trip.fare!.toStringAsFixed(2)}');

    // Finalizar la transacción de débito en el backend (cierre de viaje)
    if (trip.idTransaccionDebito != null) {
      final success = await walletService.endTripDebit(
        idTransaccionDebito: trip.idTransaccionDebito!,
        amount: trip.fare!,
        lat: lat,
        lon: lon,
        numeroSerieMonedero: numeroSerieMonedero,
      );

      if (success) {
        appLogger.i('✅ Transacción de cierre completada exitosamente');
      } else {
        appLogger.w('⚠️ No se pudo finalizar la transacción en el backend, pero el viaje se completó localmente');
      }
    } else {
      appLogger.w('⚠️ No hay ID de transacción para finalizar');
    }

    appLogger.i('✅ Viaje finalizado para monedero: $numeroSerieMonedero');
    appLogger.i('   - Distancia recorrida: ${trip.distance!.toStringAsFixed(2)} metros');
    appLogger.i('   - Tarifa: \$${trip.fare!.toStringAsFixed(2)}');

    // Remover del mapa de viajes activos
    _activeTrips.remove(numeroSerieMonedero);
    
    // Si no hay más viajes activos, detener la escucha del GPS
    if (_activeTrips.isEmpty) {
      _stopListeningToGps();
    }
    
    notifyListeners();

    return trip;
  }

  /// Obtiene un viaje activo por número de serie
  DynamicFareTrip? getActiveTrip(String numeroSerieMonedero) {
    return _activeTrips[numeroSerieMonedero];
  }

  /// Verifica si hay un viaje activo para un monedero
  bool hasActiveTrip(String numeroSerieMonedero) {
    return _activeTrips.containsKey(numeroSerieMonedero);
  }

  /// Cancela un viaje activo (sin finalizarlo)
  bool cancelTrip(String numeroSerieMonedero) {
    final removed = _activeTrips.remove(numeroSerieMonedero);
    if (removed != null) {
      appLogger.i('Viaje cancelado para monedero: $numeroSerieMonedero');
      
      // Si no hay más viajes activos, detener la escucha del GPS
      if (_activeTrips.isEmpty) {
        _stopListeningToGps();
      }
      
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Limpia todos los viajes activos
  void clearAllTrips() {
    _activeTrips.clear();
    
    // Detener la escucha del GPS
    _stopListeningToGps();
    
    appLogger.i('Todos los viajes activos han sido limpiados');
    notifyListeners();
  }
}

final dynamicFareService = DynamicFareService();

