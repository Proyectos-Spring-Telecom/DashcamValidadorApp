import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/auth_tokens.dart';
import '../models/login_response.dart';
import '../services/http_service.dart';
import '../services/storage_service.dart';
import '../services/device_registration_service.dart';
import '../services/error_handler_service.dart';
import '../services/device_service.dart';
import '../services/global_gps_service.dart';
import '../config/app_config.dart';
import '../services/position_service.dart';
import '../utils/logger.dart';

/// Controlador de autenticación que consume el servicio real de DashCam.
/// Maneja el estado de autenticación y la persistencia de sesión.
///
/// Flujo:
/// 1. POST `/login` o `/login/operador/login` → `{ token, refreshToken }`
/// 2. Guardar tokens y Authorization Bearer
/// 3. GET `/login/me` → perfil (antes venía en el body del login)
class AuthController extends ChangeNotifier {
  String? _token;
  String? _refreshToken;
  LoginResponse? _loginResponse;
  String? _errorMessage;
  String? _idTurno;
  String? _idViaje;
  /// Último Device ID / validadorId resuelto en el login (para mostrar en UI / debug).
  String? _lastDeviceValidadorId;

  final HttpService _httpService = httpService;
  final StorageService _storage = StorageService();
  final DeviceRegistrationService _deviceRegistration = deviceRegistrationService;
  final ErrorHandlerService _errorHandler = errorHandler;

  bool get isLoggedIn => _token != null && _loginResponse != null;
  LoginResponse? get loginResponse => _loginResponse;
  String? get user => _loginResponse?.userName;
  String? get token => _token;
  String? get refreshToken => _refreshToken;
  String? get errorMessage => _errorMessage;

  String? get nombreCompleto => _loginResponse?.nombreCompleto;
  String? get fotoPerfil => _loginResponse?.fotoPerfil;
  String? get nombreCliente => _loginResponse?.nombreClienteCompleto;
  UserRole? get rol => _loginResponse?.rol;

  /// numeroSerieValidador (validadorId de `/login/me`)
  String? get numeroSerieValidador => _loginResponse?.validadorId;
  String? get idTurno => _idTurno;
  String? get idViaje => _idViaje;
  String? get lastDeviceValidadorId => _lastDeviceValidadorId;

  void _logDeviceValidadorId(String source, String deviceId) {
    _lastDeviceValidadorId = deviceId;
    // print plano: fácil de ver en `flutter run` (sin PrettyPrinter).
    // ignore: avoid_print
    print('');
    // ignore: avoid_print
    print('========== DEVICE ID / validadorId ==========');
    // ignore: avoid_print
    print('Origen : $source');
    // ignore: avoid_print
    print('Valor  : $deviceId');
    // ignore: avoid_print
    print('=============================================');
    // ignore: avoid_print
    print('');
    appLogger.i('🆔 Device ID / validadorId ($source) = $deviceId');
  }

  Future<void> initialize() async {
    appLogger.i('Inicializando AuthController');
    _httpService.onSessionExpired = () {
      appLogger.w('Sesión expirada (refresh fallido); cerrando sesión local');
      unawaited(_handleSessionExpired());
    };
    _httpService.onTokensRefreshed = (tokens) {
      _token = tokens.token;
      _refreshToken = tokens.refreshToken;
      appLogger.d('AuthController: tokens en memoria actualizados tras refresh');
    };
    await _restoreSession();
  }

  Future<void> _handleSessionExpired() async {
    positionService.stop();
    try {
      await globalGpsService.stopPersistent();
    } catch (_) {}
    _errorMessage = 'Tu sesión expiró. Inicia sesión nuevamente.';
    await _clearLocalSession();
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    try {
      final token = await _storage.getToken();
      final refresh = await _storage.getRefreshToken();
      if (token == null || token.isEmpty) return;

      _token = token;
      _refreshToken = refresh;
      await _httpService.setAuthTokens(
        token: token,
        refreshToken: refresh ?? '',
      );
      appLogger.i('Token restaurado; consultando /login/me…');

      final profile = await _fetchLoginMe(
        token: token,
        refreshToken: refresh ?? '',
      );
      if (profile != null) {
        await _applyProfile(profile);
        appLogger.i('Sesión restaurada desde /login/me');
        notifyListeners();
      } else {
        appLogger.w('No se pudo restaurar perfil; limpiando sesión');
        await _clearLocalSession();
      }
    } catch (e) {
      appLogger.e('Error al restaurar sesión', e);
      await _clearLocalSession();
    }
  }

  /// Login con usuario y contraseña → tokens → `/login/me`
  Future<bool> login(String userName, String password) async {
    try {
      _errorMessage = null;
      appLogger.i('Iniciando login para usuario: $userName');

      final deviceValidadorId = await DeviceService.getDeviceId();
      _logDeviceValidadorId('login password', deviceValidadorId);

      final response = await _httpService.dio.post(
        AppConfig.endpointLogin,
        data: {
          'userName': userName,
          'password': password,
        },
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return await _completeLoginFromTokens(response.data);
      }

      _errorMessage = 'Error en la autenticación';
      appLogger.w('Respuesta inesperada del servidor: ${response.statusCode}');
      notifyListeners();
      return false;
    } on DioException catch (e) {
      _errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error en login', e);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error inesperado en login', e);
      notifyListeners();
      return false;
    }
  }

  /// Login con código (PIN) → tokens → `/login/me`
  Future<bool> loginWithCodigo(String codigo) async {
    try {
      _errorMessage = null;
      final storedUserName = await _storage.getUserName();

      if (storedUserName == null || storedUserName.isEmpty) {
        _errorMessage =
            'No hay usuario guardado. Inicia sesión con tu contraseña primero.';
        notifyListeners();
        return false;
      }

      appLogger.i('Iniciando login con código para usuario: $storedUserName');
      final validadorId = await DeviceService.getDeviceId();
      _logDeviceValidadorId('login PIN (body)', validadorId);

      final requestData = {
        'userName': storedUserName,
        'codigohash': codigo,
        'validadorId': validadorId,
      };
      appLogger.d('Body de la petición: $requestData');

      final response = await _httpService.dio.post(
        AppConfig.endpointLoginWithPin,
        data: requestData,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        return await _completeLoginFromTokens(response.data);
      }

      _errorMessage = 'Error en la autenticación con código';
      appLogger.w(
        'Respuesta inesperada en login con código: ${response.statusCode}',
      );
      notifyListeners();
      return false;
    } on DioException catch (e) {
      _errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error en login con código', e);
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = _errorHandler.handleError(e);
      appLogger.e('Error inesperado en login con código', e);
      notifyListeners();
      return false;
    }
  }

  /// 1) Parsea `{ token, refreshToken }`
  /// 2) Guarda tokens + Authorization
  /// 3) GET `/login/me` y aplica el perfil
  Future<bool> _completeLoginFromTokens(dynamic data) async {
    if (data is! Map) {
      _errorMessage = 'Respuesta de login inválida';
      notifyListeners();
      return false;
    }

    final tokens = AuthTokens.fromJson(Map<String, dynamic>.from(data));
    if (!tokens.isValid) {
      _errorMessage = 'Error: No se recibió token de autenticación';
      appLogger.e('Login exitoso pero sin token');
      notifyListeners();
      return false;
    }

    _token = tokens.token;
    _refreshToken = tokens.refreshToken;
    await _httpService.setAuthTokens(
      token: tokens.token,
      refreshToken: tokens.refreshToken,
    );
    appLogger.i('Tokens guardados; obteniendo perfil /login/me…');

    final profile = await _fetchLoginMe(
      token: tokens.token,
      refreshToken: tokens.refreshToken,
    );
    if (profile == null) {
      _errorMessage = 'No se pudo obtener el perfil del operador (/login/me)';
      await _clearLocalSession();
      notifyListeners();
      return false;
    }

    return await _handleLoginSuccess(profile);
  }

  Future<LoginResponse?> _fetchLoginMe({
    required String token,
    String refreshToken = '',
  }) async {
    try {
      final response = await _httpService.dio.get(AppConfig.endpointLoginMe);
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        appLogger.w('/login/me status inesperado: ${response.statusCode}');
        return null;
      }
      if (response.data is! Map) {
        appLogger.w('/login/me body inválido');
        return null;
      }
      return LoginResponse.fromJson(
        Map<String, dynamic>.from(response.data as Map),
        token: token,
        refreshToken: refreshToken,
      );
    } on DioException catch (e) {
      appLogger.e('Error en /login/me', e);
      return null;
    } catch (e) {
      appLogger.e('Error inesperado en /login/me', e);
      return null;
    }
  }

  Future<void> _applyProfile(LoginResponse loginResponse) async {
    _loginResponse = loginResponse;
    _token = loginResponse.token.isNotEmpty ? loginResponse.token : _token;
    _refreshToken = loginResponse.refreshToken.isNotEmpty
        ? loginResponse.refreshToken
        : _refreshToken;

    await _storage.saveUserInfo(
      userId: loginResponse.id.toString(),
      userName: loginResponse.userName,
    );
    await _storage.saveCodigoStatus(loginResponse.pinExist == 1);

    if (loginResponse.validadorId != null &&
        loginResponse.validadorId!.isNotEmpty) {
      await _storage.saveNumeroSerieValidador(loginResponse.validadorId!);
    }

    _idTurno = loginResponse.idTurno;
    _idViaje = loginResponse.idViaje;
    if (_idTurno != null && _idTurno!.isNotEmpty) {
      await _storage.saveTurnId(_idTurno!);
    } else {
      await _storage.clearTurnId();
    }
    if (_idViaje != null && _idViaje!.isNotEmpty) {
      await _storage.saveTripId(_idViaje!);
    } else {
      await _storage.clearTripId();
    }
  }

  Future<bool> _handleLoginSuccess(LoginResponse loginResponse) async {
    if (!loginResponse.esOperador) {
      _errorMessage =
          'Acceso denegado. Solo usuarios con rol "Operador" pueden acceder a esta aplicación.';
      appLogger.w(
        'Intento de login con rol no permitido: ${loginResponse.rol.nombre}',
      );
      await _clearLocalSession();
      notifyListeners();
      return false;
    }

    await _applyProfile(loginResponse);

    String currentDeviceId = '';
    try {
      currentDeviceId = await DeviceService.getDeviceId().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          appLogger.w('Timeout al obtener Device ID, usando ID del servidor');
          return loginResponse.deviceId ?? '';
        },
      );
    } catch (e) {
      appLogger.w('Error al obtener Device ID: $e, usando ID del servidor');
      currentDeviceId = loginResponse.deviceId ?? '';
    }

    if (currentDeviceId.isNotEmpty) {
      try {
        final deviceRegistered = await _deviceRegistration
            .registerDevice(loginResponse.userName, loginResponse.idCliente)
            .timeout(const Duration(seconds: 10), onTimeout: () {
          appLogger.w('Timeout al registrar dispositivo, continuando con login');
          return false;
        });

        if (!deviceRegistered) {
          appLogger.w(
            'No se pudo registrar/actualizar dispositivo. Continuando con login.',
          );
        } else {
          appLogger.i('Dispositivo registrado/actualizado exitosamente.');
        }
      } catch (e) {
        appLogger.w('Error al registrar dispositivo: $e, continuando con login');
      }
    } else {
      appLogger.w('No se pudo obtener Device ID, omitiendo registro de dispositivo');
    }

    appLogger.i('Login completado exitosamente');
    notifyListeners();
    unawaited(_activateGpsAfterLogin());
    return true;
  }

  Future<void> _activateGpsAfterLogin() async {
    try {
      await globalGpsService.startPersistent();
      appLogger.i('GPS activado en modo persistente después del login');
    } catch (e, st) {
      appLogger.w('Error al activar GPS en modo persistente: $e', e, st);
    }
  }

  /// Limpia sesión en memoria y tokens.
  /// Por defecto conserva correo + pinExist para login con código.
  Future<void> _clearLocalSession({bool keepOperatorForPinLogin = true}) async {
    _token = null;
    _refreshToken = null;
    _loginResponse = null;
    _idTurno = null;
    _idViaje = null;
    await _httpService.clearAuth();
    if (keepOperatorForPinLogin) {
      await _storage.clearSessionKeepOperator();
      appLogger.i(
        'Sesión cerrada; se conservan usuario y código para login con PIN',
      );
    } else {
      await _storage.clearUserInfo();
    }
  }

  Future<void> logout() async {
    appLogger.i('Cerrando sesión');

    try {
      await globalGpsService.stopPersistent();
      appLogger.i('GPS desactivado del modo persistente');
    } catch (e) {
      appLogger.w('Error al desactivar GPS en modo persistente: $e');
    }

    positionService.stop();

    _errorMessage = null;
    // Conservar userName + pinExist → pantalla de login con código
    await _clearLocalSession(keepOperatorForPinLogin: true);
    notifyListeners();
  }

  /// Olvida el operador guardado (correo/código) para que otro usuario
  /// pueda iniciar sesión con contraseña en este dispositivo.
  Future<void> clearStoredOperatorForOtherUser() async {
    await _storage.clearStoredOperator();
    appLogger.i('Operador guardado eliminado; se puede iniciar con otra cuenta');
  }

  Future<void> refreshTurnIdFromStorage() async {
    _idTurno = await _storage.getTurnId();
    notifyListeners();
  }

  void clearTurnIdInMemory() {
    _idTurno = null;
    notifyListeners();
  }

  Future<void> refreshViajeIdFromStorage() async {
    _idViaje = await _storage.getTripId();
    notifyListeners();
  }

  void clearViajeIdInMemory() {
    _idViaje = null;
    notifyListeners();
  }
}

final auth = AuthController();
