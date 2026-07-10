import 'dart:convert';

/// Datos extraídos de un código QR para débito en viaje.
class QrDebitPayload {
  final String numeroSerieMonedero;
  final String idCard;
  final bool esMultiple;
  final int cantidadPasajes;

  bool get isValid => numeroSerieMonedero.isNotEmpty;

  const QrDebitPayload({
    required this.numeroSerieMonedero,
    this.idCard = '',
    this.esMultiple = false,
    this.cantidadPasajes = 1,
  });
}

/// Interpreta el texto del QR.
///
/// Formato principal (generado en app/web):
/// `{ saldo, numeroSerie, idMonedero, idPasajero, numeroPasajes }`
/// - [numeroPasajes] → [cantidadPasajes] en la petición de débito.
/// - Si [numeroPasajes] > 1 → [esMultiple] = true.
///
/// También admite texto plano (serie) o JSON legacy (`cantidadPasajes`, etc.).
QrDebitPayload parseQrDebitPayload(String raw) {
  final t = raw.trim();
  if (t.isEmpty) {
    return const QrDebitPayload(numeroSerieMonedero: '');
  }

  if (t.startsWith('{')) {
    try {
      final decoded = jsonDecode(t);
      if (decoded is Map<String, dynamic>) {
        final m = decoded;
        final serieRaw = m['numeroSerieMonedero'] ??
            m['numeroSerie'] ??
            m['serie'] ??
            m['monedero'];
        final serieStr = serieRaw?.toString().trim() ?? '';

        // idCard: explícito o idMonedero del QR de pasajero/monedero
        String idCard = m['idCard']?.toString().trim() ?? '';
        if (idCard.isEmpty && m['idMonedero'] != null) {
          idCard = m['idMonedero'].toString().trim();
        }

        // cantidadPasajes en API = numeroPasajes del QR (prioridad sobre aliases)
        int cant = 0;
        if (m['numeroPasajes'] != null) {
          cant = int.tryParse(m['numeroPasajes'].toString()) ?? 0;
        } else if (m['cantidadPasajes'] != null) {
          cant = int.tryParse(m['cantidadPasajes'].toString()) ?? 0;
        } else if (m['cantidad'] != null) {
          cant = int.tryParse(m['cantidad'].toString()) ?? 0;
        }

        bool esMultiple = m['esMultiple'] == true ||
            m['esMultiple'] == 1 ||
            m['multiple'] == true;

        if (cant > 1) {
          esMultiple = true;
        }

        if (serieStr.isEmpty) {
          return QrDebitPayload(
            numeroSerieMonedero: '',
            idCard: idCard,
            esMultiple: esMultiple,
            cantidadPasajes: cant > 0 ? cant : 0,
          );
        }

        if (cant <= 0) {
          cant = esMultiple ? 2 : 1;
        }

        return QrDebitPayload(
          numeroSerieMonedero: serieStr,
          idCard: idCard,
          esMultiple: esMultiple,
          cantidadPasajes: cant,
        );
      }
    } catch (_) {
      // continúa como texto plano
    }
  }

  return QrDebitPayload(
    numeroSerieMonedero: t,
    idCard: '',
    esMultiple: false,
    cantidadPasajes: 1,
  );
}
