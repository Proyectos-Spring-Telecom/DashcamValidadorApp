import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/auth_tokens.dart';
import '../utils/jwt_utils.dart';
import '../utils/logger.dart';
import 'storage_service.dart';

/// Servicio HTTP centralizado con instancia única de Dio.
/// Incluye refresh de sesión vía POST `/login/refresh`.
class HttpService {
  static final HttpService _instance = HttpService._internal();
  factory HttpService() => _instance;
  HttpService._internal();

  late final Dio _dio;
  /// Cliente sin interceptores de auth (evita bucles al refrescar).
  late final Dio _refreshDio;
  final StorageService _storage = StorageService();

  /// Se invoca cuando el refresh falla y la sesión ya no es válida.
  VoidCallback? onSessionExpired;

  /// Se invoca tras un refresh exitoso (para sincronizar auth en memoria).
  void Function(AuthTokens tokens)? onTokensRefreshed;

  /// Cola única: varias peticiones 401 compartirán el mismo refresh.
  Future<AuthTokens?>? _refreshInFlight;

  static const String _extraRetriedAfterRefresh = 'retriedAfterRefresh';

  Future<void> initialize() async {
    final baseOptions = BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      headers: AppConfig.defaultHeaders,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
    );

    _dio = Dio(baseOptions);
    _refreshDio = Dio(baseOptions);

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_isAuthEndpoint(options.path)) {
            handler.next(options);
            return;
          }

          await _maybeRefreshProactively();

          final token = await _storage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          await _handleUnauthorized(error, handler);
        },
      ),
    );

    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retries: AppConfig.maxRetries,
        retryDelays: [
          AppConfig.retryDelay,
          AppConfig.retryDelay * 2,
          AppConfig.retryDelay * 3,
        ],
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
      ));
    }
  }

  Dio get dio => _dio;

  Future<void> setAuthToken(String? token) async {
    if (token != null && token.isNotEmpty) {
      await _storage.saveToken(token);
    } else {
      await _storage.clearToken();
    }
  }

  Future<void> setAuthTokens({
    required String token,
    String refreshToken = '',
  }) async {
    await _storage.saveAuthTokens(token: token, refreshToken: refreshToken);
  }

  Future<void> clearAuth() async {
    await _storage.clearAuthTokens();
  }

  bool _isAuthEndpoint(String path) {
    final p = path.toLowerCase();
    return p.contains(AppConfig.endpointLoginRefresh) ||
        p.endsWith(AppConfig.endpointLogin) ||
        p.contains(AppConfig.endpointLoginWithPin) ||
        p.endsWith('/login') ||
        p.contains('/login/operador/login');
  }

  /// Renueva el access token si está por expirar (antes de que falle la API).
  Future<void> _maybeRefreshProactively() async {
    final token = await _storage.getToken();
    final refresh = await _storage.getRefreshToken();
    if (token == null ||
        token.isEmpty ||
        refresh == null ||
        refresh.isEmpty) {
      return;
    }
    if (!JwtUtils.isExpiredOrExpiringSoon(token)) return;

    appLogger.i('Access token por expirar; renovando proactivamente…');
    await _refreshTokens();
  }

  Future<void> _handleUnauthorized(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final status = error.response?.statusCode;
    final options = error.requestOptions;

    if (status != 401 || _isAuthEndpoint(options.path)) {
      handler.next(error);
      return;
    }

    if (options.extra[_extraRetriedAfterRefresh] == true) {
      await _invalidateSession();
      handler.next(error);
      return;
    }

    final tokens = await _refreshTokens();
    if (tokens == null || !tokens.isValid) {
      await _invalidateSession();
      handler.next(error);
      return;
    }

    try {
      options.headers['Authorization'] = 'Bearer ${tokens.token}';
      options.extra[_extraRetriedAfterRefresh] = true;
      final response = await _dio.fetch(options);
      handler.resolve(response);
    } catch (e) {
      if (e is DioException) {
        handler.next(e);
      } else {
        handler.next(error);
      }
    }
  }

  /// Refresh de cola única. Devuelve nuevos tokens o null si falla.
  Future<AuthTokens?> _refreshTokens() {
    _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
    return _refreshInFlight!;
  }

  Future<AuthTokens?> _doRefresh() async {
    final refreshToken = await _storage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      appLogger.w('No hay refreshToken guardado; no se puede renovar la sesión');
      return null;
    }

    try {
      appLogger.i('POST ${AppConfig.endpointLoginRefresh}');
      final response = await _refreshDio.post(
        AppConfig.endpointLoginRefresh,
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data is! Map) {
        appLogger.w('Refresh fallido: status=${response.statusCode}');
        return null;
      }

      final tokens = AuthTokens.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
      if (!tokens.isValid) {
        appLogger.w('Refresh sin access token válido');
        return null;
      }

      await setAuthTokens(
        token: tokens.token,
        refreshToken: tokens.refreshToken.isNotEmpty
            ? tokens.refreshToken
            : refreshToken,
      );
      appLogger.i('Tokens renovados correctamente');
      onTokensRefreshed?.call(
        AuthTokens(
          token: tokens.token,
          refreshToken: tokens.refreshToken.isNotEmpty
              ? tokens.refreshToken
              : refreshToken,
        ),
      );
      return tokens;
    } on DioException catch (e) {
      appLogger.e('Error al refrescar token: ${e.response?.statusCode}', e);
      return null;
    } catch (e) {
      appLogger.e('Error inesperado al refrescar token', e);
      return null;
    }
  }

  Future<void> _invalidateSession() async {
    appLogger.w('Sesión inválida; limpiando tokens');
    await clearAuth();
    onSessionExpired?.call();
  }

  /// Permite forzar un refresh (p. ej. tests o arranque).
  Future<bool> refreshSession() async {
    final tokens = await _refreshTokens();
    return tokens != null && tokens.isValid;
  }
}

/// Interceptor para reintentos automáticos (timeouts / 5xx). No reintenta 401.
class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;

  RetryInterceptor({
    required this.dio,
    required this.retries,
    required this.retryDelays,
  });

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final options = err.requestOptions;
    final retryCount = options.extra['retryCount'] as int? ?? 0;
    final shouldRetry = _shouldRetry(err) && retryCount < retries;

    if (shouldRetry) {
      final delay = retryCount < retryDelays.length
          ? retryDelays[retryCount]
          : retryDelays.last;

      await Future.delayed(delay);
      options.extra['retryCount'] = retryCount + 1;

      try {
        final response = await dio.fetch(options);
        handler.resolve(response);
        return;
      } catch (_) {}
    }

    handler.next(err);
  }

  bool _shouldRetry(DioException error) {
    if (error.response?.statusCode == 401) return false;
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        (error.response?.statusCode != null &&
            error.response!.statusCode! >= 500);
  }
}

final httpService = HttpService();
