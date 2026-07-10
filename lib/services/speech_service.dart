import 'package:flutter_tts/flutter_tts.dart';

import '../utils/logger.dart';

/// Anuncios por voz (TTS del sistema).
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _ensureReady() async {
    if (_initialized) return;
    try {
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);

      for (final lang in ['es-MX', 'es-ES', 'es-US', 'es']) {
        final ok = await _tts.setLanguage(lang);
        if (ok == 1 || ok == true) break;
      }

      _initialized = true;
    } catch (e, st) {
      appLogger.w('No se pudo inicializar TTS: $e', e, st);
    }
  }

  Future<void> _speak(String text) async {
    await _ensureReady();
    if (!_initialized) return;
    try {
      await _tts.stop();
      await _tts.speak(text);
      appLogger.i('TTS: $text');
    } catch (e, st) {
      appLogger.w('Error al reproducir TTS: $e', e, st);
    }
  }

  /// Anuncia cuántos pasajes se cobrarán en un débito múltiple.
  Future<void> announceMultipleTripCharge(int cantidadPasajes) async {
    if (cantidadPasajes <= 1) return;
    final text = 'Se cobrarán $cantidadPasajes pasajes';
    await _speak(text);
  }

  /// Confirma por voz un cobro múltiple exitoso.
  Future<void> announceMultipleTripChargeSuccess(int cantidadPasajes) async {
    if (cantidadPasajes <= 1) return;
    final text = cantidadPasajes == 1
        ? 'Cobro de un pasaje realizado'
        : 'Cobro de $cantidadPasajes pasajes realizado';
    await _speak(text);
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}

final speechService = SpeechService.instance;
