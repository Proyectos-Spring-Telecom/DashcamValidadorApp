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
      appLogger.i('🔄 ========== INICIANDO OBTENCIÓN DE ACTIVIDAD ==========');
      appLogger.i('📅 Timestamp: ${DateTime.now().toIso8601String()}');

      // Obtener el número de serie del validador guardado previamente
      String? numeroSerieValidador = await _storage.getNumeroSerieValidador();
      appLogger.i('🔍 NumeroSerieValidador desde storage: ${numeroSerieValidador ?? "null"}');
      
      // Si no está guardado, intentar obtenerlo del dispositivo y guardarlo
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.w('⚠️ NumeroSerieValidador no encontrado en storage, obteniendo del dispositivo...');
        numeroSerieValidador = await deviceApiService.getValidadorSerie();
        if (numeroSerieValidador != null && numeroSerieValidador.isNotEmpty) {
          // Guardarlo para uso futuro
          await _storage.saveNumeroSerieValidador(numeroSerieValidador);
          appLogger.i('✅ NumeroSerieValidador guardado en storage: $numeroSerieValidador');
        }
      } else {
        appLogger.i('✅ NumeroSerieValidador encontrado en storage: $numeroSerieValidador');
      }
      
      if (numeroSerieValidador == null || numeroSerieValidador.isEmpty) {
        appLogger.e('❌ No se pudo obtener número de serie del validador');
        return null;
      }

      // Construir la URL con el numeroSerieValidador concatenado
      final url = '${AppConfig.endpointActivity}$numeroSerieValidador';
      final fullUrl = '${AppConfig.apiBaseUrl}$url';

      appLogger.i('🔗 ========== CONSTRUYENDO URL DEL API ==========');
      appLogger.i('   - Base URL: ${AppConfig.apiBaseUrl}');
      appLogger.i('   - Endpoint: ${AppConfig.endpointActivity}');
      appLogger.i('   - NumeroSerieValidador: $numeroSerieValidador');
      appLogger.i('   - URL relativa: $url');
      appLogger.i('   - URL completa: $fullUrl');
      appLogger.i('===============================================');

      // Hacer la petición GET al endpoint
      appLogger.i('📤 ========== EJECUTANDO PETICIÓN GET ==========');
      appLogger.i('   - Método: GET');
      appLogger.i('   - URL: $url');
      appLogger.i('   - URL completa: $fullUrl');
      appLogger.i('===========================================');
      final response = await _httpService.dio.get(url);
      appLogger.i('📥 ========== RESPUESTA RECIBIDA ==========');
      appLogger.i('   - Status Code: ${response.statusCode}');
      appLogger.i('   - Headers: ${response.headers}');
      appLogger.i('==========================================');

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        appLogger.i('✅ Actividad obtenida exitosamente');
        
        // Log completo del response
        appLogger.i('📦 ========== RESPONSE COMPLETO DEL API ==========');
        appLogger.i('${response.data}');
        appLogger.i('================================================');
        
        // Parsear la respuesta
        try {
          final responseData = response.data as Map<String, dynamic>;
          
          // Log detallado de la estructura
          appLogger.i('📋 ========== ESTRUCTURA DEL RESPONSE ==========');
          appLogger.i('   - Tipo de response.data: ${responseData.runtimeType}');
          appLogger.i('   - Tiene "data": ${responseData.containsKey("data")}');
          if (responseData.containsKey("data")) {
            final data = responseData["data"] as Map<String, dynamic>?;
            if (data != null) {
              appLogger.i('   - Tipo de "data": ${data.runtimeType}');
              appLogger.i('   - Tiene "viajes": ${data.containsKey("viajes")}');
              appLogger.i('   - Tiene "ultimaPosicion": ${data.containsKey("ultimaPosicion")}');
              if (data.containsKey("viajes")) {
                final viajes = data["viajes"];
                appLogger.i('   - Tipo de "viajes": ${viajes.runtimeType}');
                if (viajes is List) {
                  appLogger.i('   - Cantidad de viajes: ${viajes.length}');
                  if (viajes.isNotEmpty) {
                    appLogger.i('   - Primer viaje: ${viajes.first}');
                  }
                } else {
                  appLogger.w('   - ⚠️ "viajes" no es una lista: $viajes');
                }
              }
              if (data.containsKey("ultimaPosicion")) {
                final ultimaPosicion = data["ultimaPosicion"];
                appLogger.i('   - Tipo de "ultimaPosicion": ${ultimaPosicion.runtimeType}');
                if (ultimaPosicion != null) {
                  appLogger.i('   - Valor de "ultimaPosicion": $ultimaPosicion');
                } else {
                  appLogger.w('   - ⚠️ "ultimaPosicion" es null');
                }
              } else {
                appLogger.w('   - ⚠️ No se encontró "ultimaPosicion" en data');
              }
            } else {
              appLogger.w('   - ⚠️ "data" es null');
            }
          } else {
            appLogger.w('   - ⚠️ No se encontró "data" en el response');
          }
          appLogger.i('===============================================');
          
          appLogger.i('🔄 ========== MAPEANDO DATOS ==========');
          final activity = ActivityResponse.fromJson(responseData);
          
          appLogger.i('✅ Datos mapeados exitosamente:');
          appLogger.i('   - Viajes encontrados: ${activity.data.viajes.length}');
          appLogger.i('   - Última posición: ${activity.data.ultimaPosicion != null ? "Sí" : "No"}');
          if (activity.data.ultimaPosicion != null) {
            appLogger.i('   - Última posición - Lat: ${activity.data.ultimaPosicion!.latitud}, Lon: ${activity.data.ultimaPosicion!.longitud}');
            appLogger.i('   - Última posición - Velocidad: ${activity.data.ultimaPosicion!.velocidad}');
            appLogger.i('   - Última posición - Dirección: ${activity.data.ultimaPosicion!.direccion}');
            appLogger.i('   - Última posición - FechaHora: ${activity.data.ultimaPosicion!.fechaHora}');
          }
          if (activity.data.viajes.isNotEmpty) {
            appLogger.i('   - Primer viaje ID: ${activity.data.viajes.first.idViaje}');
            appLogger.i('   - Primer viaje - FechaInicio: ${activity.data.viajes.first.fechaInicio}');
          }
          appLogger.i('=====================================');
          
          return activity;
        } catch (e, stackTrace) {
          appLogger.e('❌ Error al parsear respuesta de actividad', e, stackTrace);
          appLogger.e('   - Response data completo: ${response.data}');
          appLogger.e('   - Tipo de response.data: ${response.data.runtimeType}');
          return null;
        }
      }

      appLogger.w('⚠️ Respuesta inesperada al obtener actividad: ${response.statusCode}');
      appLogger.w('   - Response data: ${response.data}');
      return null;
    } on DioException catch (e) {
      final msg = _errorHandler.handleError(e);
      appLogger.e('❌ DioException al obtener actividad: $msg', e);
      appLogger.e('   - Tipo de error: ${e.type}');
      appLogger.e('   - Mensaje: ${e.message}');
      appLogger.e('   - Status Code: ${e.response?.statusCode}');
      appLogger.e('   - Response Data: ${e.response?.data}');
      appLogger.e('   - Request Path: ${e.requestOptions.path}');
      appLogger.e('   - Request URL: ${e.requestOptions.uri}');

      // Log adicional del error del servidor si está disponible
      if (e.response != null) {
        appLogger.e('📦 Respuesta completa del servidor: ${e.response?.data}');
      }

      return null;
    } catch (e, stackTrace) {
      appLogger.e('❌ Error inesperado al obtener actividad', e, stackTrace);
      appLogger.e('   - Tipo de error: ${e.runtimeType}');
      appLogger.e('   - Mensaje: ${e.toString()}');
      return null;
    }
  }
}

// Instancia global del servicio
final activityService = ActivityService();
