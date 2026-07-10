import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Servicio para almacenamiento seguro de datos sensibles
/// Usa flutter_secure_storage para tokens y credenciales
class StorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  // Keys para almacenamiento
  static const String _keyToken = 'auth_token';
  static const String _keyRefreshToken = 'auth_refresh_token';
  static const String _keyUserId = 'user_id';
  static const String _keyUserName = 'user_name';
  static const String _keyCodigoStatus = 'user_has_codigo';
  static const String _keyNumeroSerieValidador = 'numero_serie_validador';
  static const String _keyTurnId = 'turn_id';
  static const String _keyTripId = 'trip_id';

  /// Guarda el token de autenticación
  Future<void> saveToken(String token) async {
    await _storage.write(key: _keyToken, value: token);
  }

  /// Obtiene el token de autenticación
  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  /// Limpia el token de autenticación
  Future<void> clearToken() async {
    await _storage.delete(key: _keyToken);
  }

  /// Guarda el refresh token
  Future<void> saveRefreshToken(String refreshToken) async {
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
  }

  /// Obtiene el refresh token
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: _keyRefreshToken);
  }

  /// Limpia el refresh token
  Future<void> clearRefreshToken() async {
    await _storage.delete(key: _keyRefreshToken);
  }

  /// Guarda token + refreshToken juntos
  Future<void> saveAuthTokens({
    required String token,
    required String refreshToken,
  }) async {
    await Future.wait([
      saveToken(token),
      if (refreshToken.isNotEmpty) saveRefreshToken(refreshToken),
    ]);
  }

  /// Limpia token y refreshToken
  Future<void> clearAuthTokens() async {
    await Future.wait([
      clearToken(),
      clearRefreshToken(),
    ]);
  }

  /// Guarda información básica del usuario
  Future<void> saveUserInfo({
    required String userId,
    required String userName,
  }) async {
    await Future.wait([
      _storage.write(key: _keyUserId, value: userId),
      _storage.write(key: _keyUserName, value: userName),
    ]);
  }

  /// Guarda el estado del código del operador (1 = existe, 0 = no existe)
  Future<void> saveCodigoStatus(bool hasCodigo) async {
    await _storage.write(key: _keyCodigoStatus, value: hasCodigo ? '1' : '0');
  }

  /// Obtiene el ID del usuario guardado
  Future<String?> getUserId() async {
    return await _storage.read(key: _keyUserId);
  }

  /// Obtiene el nombre de usuario guardado
  Future<String?> getUserName() async {
    return await _storage.read(key: _keyUserName);
  }

  /// Obtiene el estado del código guardado
  Future<bool> getCodigoStatus() async {
    final value = await _storage.read(key: _keyCodigoStatus);
    return value == '1';
  }

  /// Cierra sesión: limpia tokens y turno/viaje.
  /// Conserva [userName] y estado de código para poder volver a entrar con PIN.
  Future<void> clearSessionKeepOperator() async {
    await clearAuthTokens();
    await clearTurnAndTripInfo();
  }

  /// Quita el operador guardado (correo + flag de código) para permitir
  /// que otro usuario inicie sesión con contraseña.
  Future<void> clearStoredOperator() async {
    await Future.wait([
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyUserName),
      _storage.delete(key: _keyCodigoStatus),
    ]);
  }

  /// Limpia toda la información del usuario (incluye correo y código).
  Future<void> clearUserInfo() async {
    await Future.wait([
      _storage.delete(key: _keyToken),
      _storage.delete(key: _keyRefreshToken),
      _storage.delete(key: _keyUserId),
      _storage.delete(key: _keyUserName),
      _storage.delete(key: _keyCodigoStatus),
    ]);
    await clearTurnAndTripInfo();
  }

  /// Verifica si hay una sesión guardada
  Future<bool> hasStoredSession() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  // --- numeroSerieValidador (validadorId desde login) ---
  Future<void> saveNumeroSerieValidador(String value) async {
    await _storage.write(key: _keyNumeroSerieValidador, value: value);
  }

  Future<String?> getNumeroSerieValidador() async {
    return await _storage.read(key: _keyNumeroSerieValidador);
  }

  // --- ID de turno activo ---
  Future<void> saveTurnId(String value) async {
    await _storage.write(key: _keyTurnId, value: value);
  }

  Future<String?> getTurnId() async {
    return await _storage.read(key: _keyTurnId);
  }

  Future<void> clearTurnId() async {
    await _storage.delete(key: _keyTurnId);
  }

  // --- ID de viaje activo ---
  Future<void> saveTripId(String value) async {
    await _storage.write(key: _keyTripId, value: value);
  }

  Future<String?> getTripId() async {
    return await _storage.read(key: _keyTripId);
  }

  Future<void> clearTripId() async {
    await _storage.delete(key: _keyTripId);
  }

  /// Alias para viaje (misma clave que trip)
  Future<void> saveViajeId(String value) async => saveTripId(value);
  Future<String?> getViajeId() async => getTripId();
  Future<void> clearViajeId() async => clearTripId();

  /// Limpia datos de turno/viaje/validador (al cerrar sesión)
  Future<void> clearTurnAndTripInfo() async {
    await Future.wait([
      _storage.delete(key: _keyNumeroSerieValidador),
      _storage.delete(key: _keyTurnId),
      _storage.delete(key: _keyTripId),
    ]);
  }
}

