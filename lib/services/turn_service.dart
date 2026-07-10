import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../services/device_api_service.dart';
import '../services/storage_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

/// Modelo para la respuesta de inicio de turno
class StartTurnResponse {
  final int id;

  StartTurnResponse({required this.id});

  factory StartTurnResponse.fromJson(Map<String, dynamic> json) {
    return StartTurnResponse(
      id: json['id'] as int,
    );
  }
}

/// Servicio para manejar los turnos
class TurnService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;
  final StorageService _storage = StorageService();

  /// Inicia un turno
  /// Retorna el ID del turno si es exitoso, null en caso contrario
  Future<int?> startTurn() async {
    try {
      appLogger.i('Iniciando turno...');

      // Verificar si ya existe un turno guardado
      final existingTurnId = await _storage.getTurnId();
      if (existingTurnId != null && existingTurnId.isNotEmpty) {
        appLogger.w('Ya existe un turno activo (ID: $existingTurnId). No se puede iniciar un nuevo turno.');
        return null;
      }

      // Obtener numeroSerieValidador (primero del storage, luego del dispositivo como fallback)
      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.w('NumeroSerieValidador no encontrado en storage, intentando obtener del dispositivo...');
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          // Guardar el valor obtenido del dispositivo para futuras operaciones
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
          appLogger.i('NumeroSerieValidador obtenido del dispositivo y guardado: $numeroSerieValidador');
        }
      } else {
        appLogger.i('NumeroSerieValidador obtenido del storage (guardado desde login): $numeroSerieValidador');
      }
      
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('No se pudo obtener número de serie del validador');
        return null;
      }

      appLogger.d('Número de serie del validador: $numeroSerieValidador');

      // Preparar el body de la petición
      final body = {
        'numeroSerieValidador': numeroSerieValidador,
      };

      appLogger.d('Enviando petición para iniciar turno: $body');

      // Hacer la petición POST al endpoint
      final response = await _httpService.dio.post(
        AppConfig.endpointStartTurn,
        data: body,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        // Parsear la respuesta - el ID está en data.data.id
        final responseData = response.data as Map<String, dynamic>;
        final data = responseData['data'] as Map<String, dynamic>?;
        
        if (data == null || data['id'] == null) {
          appLogger.e('La respuesta no contiene el ID del turno en data');
          return null;
        }
        
        final turnId = data['id'] as int;
        appLogger.i('✅ Turno iniciado exitosamente con ID: $turnId');

        // Guardar el ID del turno en el almacenamiento
        await _storage.saveTurnId(turnId.toString());

        return turnId;
      }

      appLogger.w('Respuesta inesperada al iniciar turno: ${response.statusCode}');
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al iniciar turno: $msg', e);

      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('Respuesta del servidor: ${e.response?.data}');
      }

      return null;
    } catch (e) {
      appLogger.e('Error inesperado al iniciar turno', e);
      return null;
    }
  }

  /// Obtiene el ID del turno activo guardado
  Future<String?> getActiveTurnId() async {
    return await _storage.getTurnId();
  }

  /// Cierra un turno
  /// Usa el ID guardado del turno activo
  /// Retorna true si es exitoso, false en caso contrario
  Future<bool> endTurn() async {
    try {
      // Obtener el ID del turno guardado
      final turnIdString = await _storage.getTurnId();
      if (turnIdString == null || turnIdString.isEmpty) {
        appLogger.e('No hay turno activo para cerrar');
        return false;
      }
      
      final turnId = int.tryParse(turnIdString);
      if (turnId == null) {
        appLogger.e('ID de turno inválido: $turnIdString');
        return false;
      }
      
      appLogger.i('Cerrando turno con ID: $turnId');

      // Obtener numeroSerieValidador (primero del storage, luego del dispositivo como fallback)
      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.w('NumeroSerieValidador no encontrado en storage, intentando obtener del dispositivo...');
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          // Guardar el valor obtenido del dispositivo para futuras operaciones
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
          appLogger.i('NumeroSerieValidador obtenido del dispositivo y guardado: $numeroSerieValidador');
        }
      } else {
        appLogger.i('NumeroSerieValidador obtenido del storage (guardado desde login): $numeroSerieValidador');
      }
      
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('No se pudo obtener número de serie del validador');
        return false;
      }

      appLogger.d('Número de serie del validador: $numeroSerieValidador');

      // Preparar el body de la petición
      final body = {
        'numeroSerieValidador': numeroSerieValidador,
      };

      appLogger.d('Enviando petición para cerrar turno: $body');

      // Hacer la petición PATCH al endpoint
      final response = await _httpService.dio.patch(
        '${AppConfig.endpointEndTurn}$turnId',
        data: body,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('✅ Turno cerrado exitosamente (ID: $turnId)');

        // Limpiar el ID del turno del almacenamiento
        await _storage.clearTurnId();

        return true;
      }

      appLogger.w('Respuesta inesperada al cerrar turno: ${response.statusCode}');
      return false;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('Error al cerrar turno: $msg', e);

      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('Respuesta del servidor: ${e.response?.data}');
      }

      return false;
    } catch (e) {
      appLogger.e('Error inesperado al cerrar turno', e);
      return false;
    }
  }

  /// Limpia el ID del turno activo
  Future<void> clearActiveTurnId() async {
    await _storage.clearTurnId();
  }
}

/// Instancia global del servicio de turnos
final turnService = TurnService();
