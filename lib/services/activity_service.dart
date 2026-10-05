import 'package:dio/dio.dart';
import '../services/http_service.dart';
import '../services/error_handler_service.dart';
import '../services/storage_service.dart';
import '../services/device_api_service.dart';
import '../config/app_config.dart';
import '../models/activity_response.dart';
import '../utils/logger.dart';

/// Servicio para obtener la actividad (viajes y última posición)
class ActivityService {
  final HttpService _httpService = httpService;
  final ErrorHandlerService _errorHandler = errorHandler;
  final StorageService _storage = StorageService();

  /// Obtiene la actividad del validador
  /// Retorna null si hay error
  Future<ActivityResponse?> getActivity() async {
    try {
      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();

      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
        }
      }

      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('No se pudo obtener número de serie del validador');
        return null;
      }

      final url = '${AppConfig.endpointActivity}$numeroSerieValidador';
      final response = await _httpService.dio.get(url);

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        try {
          final responseData = response.data as Map<String, dynamic>;
          return ActivityResponse.fromJson(responseData);
        } catch (e, stackTrace) {
          appLogger.e('Error al parsear respuesta de actividad');
          return null;
        }
      }

      appLogger.w(
        'Respuesta inesperada al obtener actividad: ${response.statusCode}',
      );
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('DioException al obtener actividad: $msg');
      return null;
    } catch (e, stackTrace) {
      appLogger.e('Error inesperado al obtener actividad');
      return null;
    }
  }
}

final activityService = ActivityService();
