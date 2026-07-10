import 'dart:math' as math;
import '../config/app_config.dart';
import '../services/native_gps_service.dart';

/// Modelo para representar un viaje activo de tarifa por metro
/// Calcula la distancia total recorrida durante el trayecto
class MeterFareTrip {
  final String numeroSerieMonedero;
  final DateTime startTime;
  final double startLat;
  final double startLon;
  int? idTransaccionDebito; // ID de la transacción creada al iniciar el viaje
  DateTime? endTime;
  double? endLat;
  double? endLon;
  
  // Distancia acumulada durante el trayecto (en metros)
  double _accumulatedDistance = 0.0;
  
  // Última ubicación GPS registrada (para calcular distancia incremental)
  NativeGpsLocationResponse? _lastLocation;
  
  // Lista de puntos GPS durante el trayecto (opcional, para debugging)
  final List<Map<String, dynamic>> _gpsPoints = [];
  
  double? distance; // distancia total acumulada en metros
  double? fare; // tarifa calculada

  MeterFareTrip({
    required this.numeroSerieMonedero,
    required this.startTime,
    required this.startLat,
    required this.startLon,
    this.idTransaccionDebito,
    this.endTime,
    this.endLat,
    this.endLon,
    this.distance,
    this.fare,
  });

  bool get isActive => endTime == null;
  bool get isCompleted => endTime != null && distance != null && fare != null;
  double get accumulatedDistance => _accumulatedDistance;
  int get gpsPointCount => _gpsPoints.length;

  /// Calcula la distancia entre dos puntos GPS en metros usando la fórmula de Haversine
  static double calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // Radio de la Tierra en metros

    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);

    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.asin(math.sqrt(a));

    return earthRadius * c;
  }

  static double _toRadians(double degrees) {
    return degrees * (3.141592653589793 / 180.0);
  }

  /// Calcula la tarifa basada en la distancia
  /// - $16 pesos por el primer kilómetro
  /// - $1 peso cada 100 metros después del primer kilómetro
  static double calculateFare(double distanceMeters) {
    final double baseFare = AppConfig.dynamicFareBase;
    final double firstKilometer = AppConfig.dynamicFareFirstKilometer;
    final double incrementDistance = AppConfig.dynamicFareIncrementDistance;
    final double incrementFare = AppConfig.dynamicFareIncrementAmount;

    if (distanceMeters <= firstKilometer) {
      return baseFare;
    }

    // Calcular metros adicionales después del primer kilómetro
    final double additionalMeters = distanceMeters - firstKilometer;
    // Calcular número de incrementos
    final int increments = (additionalMeters / incrementDistance).ceil();

    return baseFare + (increments * incrementFare);
  }

  /// Actualiza la distancia acumulada con una nueva ubicación GPS
  /// Se llama cada vez que hay una actualización GPS durante el viaje activo
  void updateLocation(NativeGpsLocationResponse location) {
    if (!isActive) return; // Solo actualizar si el viaje está activo
    
    // Si es la primera ubicación después del inicio, solo guardarla
    if (_lastLocation == null) {
      _lastLocation = location;
      _gpsPoints.add({
        'lat': location.lat,
        'lon': location.lon,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'distance': 0.0,
      });
      return;
    }

    // Calcular distancia entre la última ubicación y la nueva
    final segmentDistance = calculateDistance(
      _lastLocation!.lat,
      _lastLocation!.lon,
      location.lat,
      location.lon,
    );

    // Filtrar saltos grandes (outliers) - más de 100 metros en una actualización
    // Esto puede indicar un error de GPS o un salto no válido
    const double maxSegmentDistance = 100.0; // metros
    if (segmentDistance > maxSegmentDistance) {
      // Ignorar este segmento si es demasiado grande (probablemente un error)
      return;
    }

    // Acumular la distancia del segmento
    _accumulatedDistance += segmentDistance;

    // Guardar el punto GPS para debugging
    _gpsPoints.add({
      'lat': location.lat,
      'lon': location.lon,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'distance': segmentDistance,
      'accumulated': _accumulatedDistance,
    });

    // Actualizar la última ubicación
    _lastLocation = location;
  }

  /// Finaliza el viaje con las coordenadas finales
  /// La distancia ya está acumulada durante el trayecto
  void completeTrip(double endLat, double endLon) {
    this.endTime = DateTime.now();
    this.endLat = endLat;
    this.endLon = endLon;
    
    // Si hay una última ubicación registrada, calcular la distancia hasta el punto final
    if (_lastLocation != null) {
      final finalSegment = calculateDistance(
        _lastLocation!.lat,
        _lastLocation!.lon,
        endLat,
        endLon,
      );
      
      // Solo agregar si el segmento final es razonable (menos de 100m)
      if (finalSegment <= 100.0) {
        _accumulatedDistance += finalSegment;
      }
    }
    
    // La distancia total es la acumulada durante todo el trayecto
    this.distance = _accumulatedDistance;
    
    // Calcular tarifa basada en la distancia total acumulada
    this.fare = calculateFare(distance!);
  }
}

