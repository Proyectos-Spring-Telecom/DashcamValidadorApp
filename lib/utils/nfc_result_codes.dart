/// Mensajes legibles para códigos del lector NFC local (`GET /nfc/m1`).
class NfcResultCodes {
  NfcResultCodes._();

  /// Errores transitorios: no hay tarjeta estable o fallo momentáneo de comunicación.
  static bool isRetryable(int result) => result == -1 || result == -5;

  static String message(int result) {
    switch (result) {
      case 0:
        return 'Éxito';
      case -1:
        return 'No hay tarjeta en el lector';
      case -2:
        return 'Error de autenticación con la tarjeta';
      case -3:
        return 'Error al leer la tarjeta';
      case -4:
        return 'Error al escribir en la tarjeta';
      case -5:
        return 'Comunicación con el lector falló. Mantén la tarjeta sobre el lector e intenta de nuevo.';
      default:
        return 'Error del lector (código: $result)';
    }
  }

  /// Traduce mensajes crudos del backend/lector a texto amigable.
  static String friendlyMessage(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return 'No se pudo completar el cobro';
    }
    final match = RegExp(r'c[oó]digo:\s*(-?\d+)', caseSensitive: false).firstMatch(raw);
    if (match != null) {
      final code = int.tryParse(match.group(1)!);
      if (code != null) return message(code);
    }
    return raw;
  }
}
