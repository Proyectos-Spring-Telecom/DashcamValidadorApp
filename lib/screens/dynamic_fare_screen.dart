import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/nfc_service.dart';
import '../services/dynamic_fare_service.dart';
import '../services/wallet_service.dart';
import '../models/dynamic_fare_trip.dart';
import '../services/global_gps_service.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

class DynamicFareScreen extends StatefulWidget {
  const DynamicFareScreen({super.key});

  @override
  State<DynamicFareScreen> createState() => _DynamicFareScreenState();
}

class _DynamicFareScreenState extends State<DynamicFareScreen> {
  String? _statusMessage;
  bool _isProcessing = false;
  bool _isReading = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // Asegurar que el GPS esté activo (aunque esté en modo persistente)
    _ensureGpsActive();
    // Actualizar la UI cada segundo para mostrar el tiempo transcurrido
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Iniciar lectura automática al entrar a la pantalla
    _startAutoRead();
  }

  /// Asegura que el GPS esté activo cuando se entra a esta vista
  void _ensureGpsActive() {
    if (!globalGpsService.isActive && !globalGpsService.isPersistent) {
      appLogger.w('GPS no está activo en tarifa dinámica, activando modo persistente...');
      globalGpsService.startPersistent().catchError((e) {
        appLogger.e('Error al activar GPS en tarifa dinámica: $e');
      });
    } else {
      appLogger.d('GPS está activo (isActive: ${globalGpsService.isActive}, isPersistent: ${globalGpsService.isPersistent})');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _isReading = false;
    super.dispose();
  }

  /// Inicia la lectura automática de tarjetas
  void _startAutoRead() {
    if (_isReading) return;
    _isReading = true;
    _readCardLoop();
  }

  /// Loop continuo de lectura de tarjetas
  Future<void> _readCardLoop() async {
    while (_isReading && mounted) {
      if (!_isProcessing) {
        setState(() {
          _statusMessage = 'Acerca la tarjeta para iniciar o finalizar un viaje';
          _isProcessing = true;
        });

        final uid = await _readCardUidWithTimeout();
        if (!mounted || !_isReading) break;

        if (uid != null) {
          await _processCard(uid);
        } else {
          if (mounted) {
            setState(() {
              _isProcessing = false;
            });
          }
        }
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  }

  /// Procesa la tarjeta leída
  Future<void> _processCard(String uid) async {
    // Verificar si el monedero existe
    final wallet = await walletService.getWalletBySerie(uid);
    if (!mounted) return;

    if (wallet == null) {
      setState(() {
        _statusMessage = 'Monedero no encontrado: $uid';
        _isProcessing = false;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
      return;
    }

    // Verificar si hay un viaje activo para este monedero
    if (dynamicFareService.hasActiveTrip(uid)) {
      // Finalizar el viaje
      final completedTrip = await dynamicFareService.endTrip(uid);
      if (!mounted) return;

      if (completedTrip != null) {
        setState(() {
          _statusMessage = '✅ Viaje finalizado\nDistancia: ${completedTrip.distance!.toStringAsFixed(2)}m\nTarifa: \$${completedTrip.fare!.toStringAsFixed(2)}';
          _isProcessing = false;
        });
        // Mostrar mensaje de éxito por 3 segundos antes de continuar
        await Future.delayed(const Duration(seconds: 3));
      } else {
        setState(() {
          _statusMessage = 'Error al finalizar el viaje.';
          _isProcessing = false;
        });
        await Future.delayed(const Duration(seconds: 2));
      }
    } else {
      // Iniciar un nuevo viaje
      final started = await dynamicFareService.startTrip(uid);
      if (!mounted) return;

      if (started) {
        setState(() {
          _statusMessage = '✅ Viaje iniciado para monedero: $uid';
          _isProcessing = false;
        });
        // Mostrar mensaje de éxito por 2 segundos antes de continuar
        await Future.delayed(const Duration(seconds: 2));
      } else {
        setState(() {
          _statusMessage = 'Error al iniciar el viaje.';
          _isProcessing = false;
        });
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
      // Reiniciar lectura automáticamente después de procesar
      if (_isReading) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted && _isReading && !_isProcessing) {
            _readCardLoop();
          }
        });
      }
    }
  }


  Future<String?> _readCardUidWithTimeout() async {
    final timeout = AppConfig.nfcCardReadTimeout;
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final response = await NfcService.readM1Card();
      if (response.isSuccess && response.cardUid != null && response.cardUid!.isNotEmpty) {
        return response.cardUid;
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    return null;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeTrips = dynamicFareService.activeTrips;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tarifa Punto a Punto'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Regresar',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: ListenableBuilder(
        listenable: dynamicFareService,
        builder: (context, _) {
          return Column(
            children: [
          // Card de estado y botón de lectura
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _isProcessing ? Colors.blue.shade50 : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (_isProcessing ? Colors.blue : cs.primary).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Animación de pulso cuando está leyendo
                      if (_isProcessing)
                        TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.8, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: value,
                              child: Icon(
                                Icons.nfc,
                                color: Colors.blue.shade700,
                                size: 64,
                              ),
                            );
                          },
                          onEnd: () {
                            if (mounted && _isProcessing) {
                              setState(() {});
                            }
                          },
                        )
                      else
                        Icon(
                          Icons.nfc,
                          color: cs.primary,
                          size: 64,
                        ),
                      const SizedBox(height: 24),
                      Text(
                        _statusMessage ?? 'Acerca la tarjeta para iniciar o finalizar un viaje',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      if (_isProcessing) ...[
                        const SizedBox(height: 16),
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Lista de viajes activos
          Expanded(
            child: activeTrips.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_car, size: 64, color: cs.onSurface.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text(
                          'No hay viajes activos',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: cs.onSurface.withOpacity(0.6),
                              ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: activeTrips.length,
                    itemBuilder: (context, index) {
                      final entry = activeTrips.entries.elementAt(index);
                      final monedero = entry.key;
                      final trip = entry.value;
                      final duration = DateTime.now().difference(trip.startTime);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.account_balance_wallet, color: cs.primary, size: 28),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Monedero: $monedero',
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      dynamicFareService.cancelTrip(monedero);
                                      setState(() {});
                                    },
                                    tooltip: 'Cancelar viaje',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoItem(
                                      'Tiempo',
                                      _formatDuration(duration),
                                      Icons.access_time,
                                      cs,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildInfoItem(
                                      'Inicio',
                                      '${trip.startTime.hour.toString().padLeft(2, '0')}:${trip.startTime.minute.toString().padLeft(2, '0')}',
                                      Icons.play_circle,
                                      cs,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Mostrar distancia acumulada en tiempo real
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.straighten, color: cs.onSecondaryContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Distancia recorrida',
                                            style: TextStyle(
                                              color: cs.onSecondaryContainer,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            '${trip.accumulatedDistance.toStringAsFixed(2)} m',
                                            style: TextStyle(
                                              color: cs.onSecondaryContainer,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.location_on, color: cs.onPrimaryContainer),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Inicio: ${trip.startLat.toStringAsFixed(6)}, ${trip.startLon.toStringAsFixed(6)}',
                                        style: TextStyle(
                                          color: cs.onPrimaryContainer,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (trip.gpsPointCount > 0) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Puntos GPS: ${trip.gpsPointCount}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: cs.onSurface.withOpacity(0.6),
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
        },
      ),
    );
  }

  Widget _buildInfoItem(String label, String value, IconData icon, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.7),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

