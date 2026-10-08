import 'package:flutter_test/flutter_test.dart';

import 'package:dashcam/utils/qr_debit_parser.dart';

void main() {
  group('parseQrDebitPayload', () {
    test('lee serie y número de pasajes del QR principal', () {
      final p = parseQrDebitPayload(
        '{"numeroSerie":"MON-ABC","idMonedero":7,"numeroPasajes":3}',
      );
      expect(p.isValid, isTrue);
      expect(p.numeroSerieMonedero, 'MON-ABC');
      expect(p.idCard, '7');
      expect(p.cantidadPasajes, 3);
      expect(p.esMultiple, isTrue);
    });

    test('un QR con un pasaje no es múltiple', () {
      final p = parseQrDebitPayload('{"numeroSerie":"MON-ABC","numeroPasajes":1}');
      expect(p.isValid, isTrue);
      expect(p.cantidadPasajes, 1);
      expect(p.esMultiple, isFalse);
    });

    test('más de 50 pasajes se rechaza en vez de recortarse', () {
      final p = parseQrDebitPayload('{"numeroSerie":"MON-ABC","numeroPasajes":80}');
      expect(p.isValid, isFalse);
      expect(p.error, contains('50'));
    });

    test('50 pasajes exactos es válido', () {
      final p = parseQrDebitPayload('{"numeroSerie":"MON-ABC","numeroPasajes":50}');
      expect(p.isValid, isTrue);
      expect(p.cantidadPasajes, 50);
    });

    test('texto plano se toma como serie', () {
      final p = parseQrDebitPayload('  MON-XYZ ');
      expect(p.isValid, isTrue);
      expect(p.numeroSerieMonedero, 'MON-XYZ');
    });

    test('vacío o sin serie es inválido sin mensaje de pasajes', () {
      expect(parseQrDebitPayload('').isValid, isFalse);
      final p = parseQrDebitPayload('{"numeroPasajes":2}');
      expect(p.isValid, isFalse);
      expect(p.error, isNull);
    });
  });
}
