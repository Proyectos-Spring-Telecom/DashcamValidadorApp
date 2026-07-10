import 'dart:convert';

/// Utilidades ligeras para JWT (sin dependencias externas).
class JwtUtils {
  JwtUtils._();

  /// Epoch en segundos del claim `exp`, o null si no se puede leer.
  static int? getExpirationSeconds(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload = _decodeBase64Url(parts[1]);
      final map = jsonDecode(payload);
      if (map is! Map) return null;
      final exp = map['exp'];
      if (exp is int) return exp;
      if (exp is num) return exp.toInt();
      if (exp is String) return int.tryParse(exp);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// True si el token ya expiró o expira en menos de [skew].
  static bool isExpiredOrExpiringSoon(
    String jwt, {
    Duration skew = const Duration(seconds: 60),
  }) {
    final exp = getExpirationSeconds(jwt);
    if (exp == null) return false;
    final expiry = DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    return DateTime.now().toUtc().isAfter(expiry.subtract(skew));
  }

  static String _decodeBase64Url(String input) {
    var output = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (output.length % 4) {
      case 0:
        break;
      case 2:
        output += '==';
        break;
      case 3:
        output += '=';
        break;
      default:
        throw FormatException('Base64URL inválido');
    }
    return utf8.decode(base64.decode(output));
  }
}
