import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../services/storage_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

/// Modelo para Zona
class Zone {
  final int id;
  final String nombre;

  Zone({required this.id, required this.nombre});

  factory Zone.fromJson(Map<String, dynamic> json) {
    return Zone(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? '',
    );
  }
}

/// Modelo para Ruta
class Road {
  final int id;
  final String nombre;

  Road({required this.id, required this.nombre});

  factory Road.fromJson(Map<String, dynamic> json) {
    return Road(
      id: json['id'] as int,
      nombre: json['nombre'] as String? ?? '',
    );
  }
}

/// Modelo para Variante
class Variant {
  final int id;
  final String nombre;

  Variant({required this.id, required this.nombre});

  factory Variant.fromJson(Map<String, dynamic> json) {
    return Variant(
      id: json['id'] as int,
      nombre: json['nombreVariante'] as String? ?? json['nombre'] as String? ?? '',
    );
  }
}

/// Servicio para manejar viajes, zonas, rutas y variantes
class TripService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;
  final StorageService _storage = StorageService();

  /// Obtiene la lista de zonas
  Future<List<Zone>> getZones() async {
    try {
      appLogger.i('Obteniendo lista de zonas...');
      final response = await _httpService.dio.get(AppConfig.endpointListZones);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final data = response.data;
        List<Zone> zones = [];

        // Manejar diferentes formatos de respuesta
        if (data is List) {
          zones = data.map((json) => Zone.fromJson(json)).toList();
        } else if (data is Map && data['data'] != null) {
          final zonesData = data['data'] as List;
          zones = zonesData.map((json) => Zone.fromJson(json)).toList();
        }

        appLogger.i('✅ Zonas obtenidas: ${zones.length}');
        return zones;
      }

      appLogger.w('Respuesta inesperada al obtener zonas: ${response.statusCode}');
      return [];
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al obtener zonas: $msg', e);
      return [];
    } catch (e) {
      appLogger.e('Error inesperado al obtener zonas', e);
      return [];
    }
  }

  /// Obtiene la lista de rutas por zona
  Future<List<Road>> getRoadsByZone(int zoneId) async {
    try {
      appLogger.i('Obteniendo rutas para zona: $zoneId');
      final url = AppConfig.endpointListRoads.replaceFirst('{idZona}', zoneId.toString());
      final response = await _httpService.dio.get(url);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final data = response.data;
        List<Road> roads = [];

        // Manejar diferentes formatos de respuesta
        if (data is List) {
          roads = data.map((json) => Road.fromJson(json)).toList();
        } else if (data is Map && data['data'] != null) {
          final roadsData = data['data'] as List;
          roads = roadsData.map((json) => Road.fromJson(json)).toList();
        }

        appLogger.i('✅ Rutas obtenidas: ${roads.length}');
        return roads;
      }

      appLogger.w('Respuesta inesperada al obtener rutas: ${response.statusCode}');
      return [];
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al obtener rutas: $msg', e);
      return [];
    } catch (e) {
      appLogger.e('Error inesperado al obtener rutas', e);
      return [];
    }
  }

  /// Obtiene la lista de variantes por ruta
  Future<List<Variant>> getVariantsByRoad(int roadId) async {
    try {
      appLogger.i('Obteniendo variantes para ruta: $roadId');
      final url = AppConfig.endpointListVariants.replaceFirst('{idRuta}', roadId.toString());
      final response = await _httpService.dio.get(url);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final data = response.data;
        List<Variant> variants = [];

        // Manejar diferentes formatos de respuesta
        if (data is List) {
          variants = data.map((json) => Variant.fromJson(json)).toList();
        } else if (data is Map && data['data'] != null) {
          final variantsData = data['data'] as List;
          variants = variantsData.map((json) => Variant.fromJson(json)).toList();
        }

        appLogger.i('✅ Variantes obtenidas: ${variants.length}');
        return variants;
      }

      appLogger.w('Respuesta inesperada al obtener variantes: ${response.statusCode}');
      return [];
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al obtener variantes: $msg', e);
      return [];
    } catch (e) {
      appLogger.e('Error inesperado al obtener variantes', e);
      return [];
    }
  }

  /// Inicia un viaje
  /// Retorna el ID del viaje si es exitoso, null en caso contrario
  Future<int?> startTrip(int idVariante) async {
    try {
      appLogger.i('Iniciando viaje con variante: $idVariante');

      // Obtener el ID del turno guardado
      final turnIdString = await _storage.getTurnId();
      if (turnIdString == null || turnIdString.isEmpty) {
        appLogger.e('No hay turno activo para iniciar viaje');
        return null;
      }

      final turnId = int.tryParse(turnIdString);
      if (turnId == null) {
        appLogger.e('ID de turno inválido: $turnIdString');
        return null;
      }

      appLogger.d('ID de turno: $turnId, ID de variante: $idVariante');

      // Preparar el body de la petición
      final body = {
        'idTurno': turnId,
        'idVariante': idVariante,
      };

      appLogger.d('Enviando petición para iniciar viaje: $body');

      // Hacer la petición POST al endpoint
      final response = await _httpService.dio.post(
        AppConfig.endpointStartTrip,
        data: body,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        // Parsear la respuesta - el ID está en data.data.id
        final responseData = response.data as Map<String, dynamic>;
        final data = responseData['data'] as Map<String, dynamic>?;
        
        if (data == null || data['id'] == null) {
          appLogger.e('La respuesta no contiene el ID del viaje en data');
          return null;
        }
        
        final tripId = data['id'] as int;
        appLogger.i('✅ Viaje iniciado exitosamente con ID: $tripId');

        // Guardar el ID del viaje en el almacenamiento
        await _storage.saveViajeId(tripId.toString());

        return tripId;
      }

      appLogger.w('Respuesta inesperada al iniciar viaje: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al iniciar viaje: $msg', e);

      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('Respuesta del servidor: ${e.response?.data}');
      }

      return null;
    } catch (e) {
      appLogger.e('Error inesperado al iniciar viaje', e);
      return null;
    }
  }

  /// Cierra un viaje
  /// Usa el ID guardado del viaje activo
  /// Retorna true si es exitoso, false en caso contrario
  Future<bool> endTrip() async {
    try {
      // Obtener el ID del viaje guardado
      final viajeIdString = await _storage.getViajeId();
      if (viajeIdString == null || viajeIdString.isEmpty) {
        appLogger.e('No hay viaje activo para cerrar');
        return false;
      }
      
      final viajeId = int.tryParse(viajeIdString);
      if (viajeId == null) {
        appLogger.e('ID de viaje inválido: $viajeIdString');
        return false;
      }
      
      appLogger.i('Cerrando viaje con ID: $viajeId');

      // Hacer la petición PATCH al endpoint
      final response = await _httpService.dio.patch(
        '${AppConfig.endpointEndTrip}$viajeId',
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('✅ Viaje cerrado exitosamente (ID: $viajeId)');

        // Limpiar el ID del viaje del almacenamiento
        await _storage.clearViajeId();

        return true;
      }

      appLogger.w('Respuesta inesperada al cerrar viaje: ${response.statusCode}');
      return false;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al cerrar viaje: $msg', e);

      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('Respuesta del servidor: ${e.response?.data}');
      }

      return false;
    } catch (e) {
      appLogger.e('Error inesperado al cerrar viaje', e);
      return false;
    }
  }

  /// Obtiene el ID del viaje activo guardado
  Future<String?> getActiveViajeId() async {
    return await _storage.getViajeId();
  }
}

/// Instancia global del servicio de viajes
final tripService = TripService();
