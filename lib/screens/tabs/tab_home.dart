import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../app/auth.dart';
import '../../services/turn_service.dart';
import '../../services/trip_service.dart';
import '../../services/nfc_service.dart';
import '../../services/trip_debit_coordinator.dart';
import '../../services/wallet_service.dart';
import '../../services/speech_service.dart';
import '../../config/app_config.dart';
import '../../widgets/gps_status_widget.dart';
import '../../utils/qr_debit_parser.dart';
import '../../utils/logger.dart';
import '../../utils/device_capabilities.dart';
import '../../widgets/debit_transaction_dialog.dart';

class TabHome extends StatelessWidget {
  const TabHome({super.key});

  @override

  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Resumen del día
        // Card(
        //   child: Padding(
        //     padding: const EdgeInsets.all(20.0),
        //     child: Column(
        //       crossAxisAlignment: CrossAxisAlignment.start,
        //       children: [
        //         Row(
        //           children: [
        //             Icon(Icons.today, color: cs.primary),
        //             const SizedBox(width: 12),
        //             Text(
        //               'Resumen del día',
        //               style: Theme.of(context)
        //                   .textTheme
        //                   .titleLarge
        //                   ?.copyWith(fontWeight: FontWeight.bold),
        //             ),
        //           ],
        //         ),
        //         const SizedBox(height: 20),
        //         Row(
        //           children: [
        //             Expanded(
        //               child: _StatCard(
        //                 icon: Icons.attach_money,
        //                 label: 'Ingresos (MN)',
        //                 value: '0',
        //                 color: cs.primary,
        //               ),
        //             ),
        //             const SizedBox(width: 12),
        //             Expanded(
        //               child: _StatCard(
        //                 icon: Icons.people,
        //                 label: 'Pasajeros',
        //                 value: '0',
        //                 color: cs.tertiary,
        //               ),
        //             ),
        //           ],
        //         ),
        //         const SizedBox(height: 12),
        //         Row(
        //           children: [
        //             Expanded(
        //               child: _StatCard(
        //                 icon: Icons.route,
        //                 label: 'Rutas',
        //                 value: '0',
        //                 color: cs.secondary,
        //               ),
        //             ),
        //             const SizedBox(width: 12),
        //             Expanded(
        //               child: _StatCard(
        //                 icon: Icons.access_time,
        //                 label: 'Viajes',
        //                 value: '0',
        //                 color: cs.tertiary,
        //               ),
        //             ),
        //           ],
        //         ),
        //       ],
        //     ),
        //   ),
        // ),
        // const SizedBox(height: 16),
        // Estado del GPS
        const GpsStatusWidget(showDetails: true, autoStart: true),
        const SizedBox(height: 12),
        // Botón Cerrar Turno / Iniciar Turno (deshabilitado si hay viaje activo)
        ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final hasTurn = auth.idTurno != null && auth.idTurno!.isNotEmpty;
            final hasViaje = auth.idViaje != null && auth.idViaje!.isNotEmpty;
            return _TurnActionButton(hasTurn: hasTurn, hasViaje: hasViaje);
          },
        ),
        const SizedBox(height: 12),
        // Botón Cerrar viaje / Iniciar Viaje (deshabilitado si no hay turno)
        ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final hasTurn = auth.idTurno != null && auth.idTurno!.isNotEmpty;
            final hasViaje = auth.idViaje != null && auth.idViaje!.isNotEmpty;
            return _TripActionButton(hasViaje: hasViaje, hasTurn: hasTurn);
          },
        ),
        ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final hasViaje = auth.idViaje != null && auth.idViaje!.isNotEmpty;
            if (!hasViaje) return const SizedBox.shrink();
            return const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 20),
                _TripDebitSection(),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Cobro con NFC / QR durante viaje activo (mismo endpoint de débito).
class _TripDebitSection extends StatefulWidget {
  const _TripDebitSection();

  @override
  State<_TripDebitSection> createState() => _TripDebitSectionState();
}

class _TripDebitSectionState extends State<_TripDebitSection> {
  /// Cobro en curso (NFC o QR); evita solapar peticiones.
  bool _processingDebit = false;

  MobileScannerController? _qrController;
  bool _qrHandling = false;
  CameraFacing _cameraFacing = CameraFacing.front;
  String? _cameraError;
  /// Si la cámara falla (p. ej. Z90N sin cámara), no volver a montar MobileScanner.
  bool _qrDisabled = false;
  bool _qrTryingFallback = false;
  bool _qrHardwareChecked = false;

  bool? _nativeNfcEnabled;
  bool? _externalReaderAvailable;

  bool get _puedeQr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Solo Android: la lectura UID nativa está cableada en [NfcService] para Android.
  bool get _puedeNfcAuto =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapDebitHardware());
  }

  Future<void> _bootstrapDebitHardware() async {
    if (_puedeQr) {
      final hasCamera = await DeviceCapabilities.hasCamera();
      if (!mounted) return;
      _qrHardwareChecked = true;
      if (!hasCamera) {
        appLogger.w('Dispositivo sin cámara; escáner QR omitido');
        setState(() {
          _qrDisabled = true;
          _cameraError =
              'Este dispositivo no tiene cámara. El cobro por QR no está disponible.';
        });
      } else {
        await _initQrScanner();
      }
    }

    if (mounted && _puedeNfcAuto) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _startNfcListenLoop();
    }
  }

  Future<void> _initQrScanner({CameraFacing? facing}) async {
    if (!_puedeQr || _qrDisabled) return;

    final target = facing ?? _cameraFacing;
    _qrController?.dispose();
    _qrController = null;
    _cameraError = null;
    if (mounted) setState(() {});

    try {
      final controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        facing: target,
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _qrController = controller;
        _cameraFacing = target;
      });
    } catch (e) {
      appLogger.w('No se pudo crear controlador cámara $target: $e');
      await _disableQrOrTryBackCamera(target);
    }
  }

  Future<void> _disableQrOrTryBackCamera(CameraFacing failedFacing) async {
    if (failedFacing == CameraFacing.front && !_qrTryingFallback) {
      _qrTryingFallback = true;
      await _initQrScanner(facing: CameraFacing.back);
      return;
    }
    if (!mounted) return;
    setState(() {
      _qrDisabled = true;
      _qrController = null;
      _cameraError =
          'Cámara no disponible en este dispositivo. El cobro por QR queda deshabilitado.';
    });
  }

  void _onScannerError(MobileScannerException error) {
    appLogger.w('Error escáner QR: ${error.errorCode} - ${error.errorDetails}');
    _qrController?.dispose();
    _qrController = null;
    if (_qrDisabled || !mounted) return;

    if (_cameraFacing == CameraFacing.front && !_qrTryingFallback) {
      _qrTryingFallback = true;
      _initQrScanner(facing: CameraFacing.back);
      return;
    }

    setState(() {
      _qrDisabled = true;
      _cameraError =
          'Cámara no disponible (${error.errorCode.name}). '
          'Usa NFC o un dispositivo con cámara para QR.';
    });
  }

  @override
  void dispose() {
    _qrController?.dispose();
    super.dispose();
  }

  /// Escucha tarjetas (NFC nativo o lector HTTP loopback) mientras haya viaje activo.
  void _startNfcListenLoop() {
    Future<void> loop() async {
      _nativeNfcEnabled = await NfcService.isNativeNfcEnabled();
      _externalReaderAvailable = await NfcService.isExternalReaderAvailable();

      if (!_nativeNfcEnabled! && !_externalReaderAvailable!) {
        appLogger.w(
          'Sin NFC nativo ni lector HTTP en 127.0.0.1:${AppConfig.localDeviceApiPort}/nfc/m1',
        );
        if (mounted) setState(() {});
        return;
      }

      if (!_nativeNfcEnabled!) {
        appLogger.i(
          'NFC nativo deshabilitado; escuchando lector HTTP '
          '127.0.0.1:${AppConfig.localDeviceApiPort}/nfc/m1',
        );
      }

      if (mounted) setState(() {});

      while (mounted) {
        if (_processingDebit) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final uid = await NfcService.readCardUidWithTimeout(
          timeout: AppConfig.nfcCardReadTimeout,
        );
        if (!mounted) break;
        if (_processingDebit) continue;
        if (uid != null && uid.isNotEmpty) {
          await _ejecutarDebitoNfc(uid);
          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 750));
          }
        }
      }
    }

    loop();
  }

  String _nfcStatusText() {
    if (_nativeNfcEnabled == true) {
      return 'Acerca el monedero al teléfono.';
    }
    if (_externalReaderAvailable == true) {
      return 'Lector activo: pasa la tarjeta por el lector.';
    }
    if (_nativeNfcEnabled == false && _externalReaderAvailable == false) {
      return 'No se detecta lector de tarjetas. Revisa la conexión del lector.';
    }
    return 'Iniciando lectura de tarjetas…';
  }

  int? _idViajeActual() {
    final idViaje = int.tryParse(auth.idViaje ?? '');
    if (idViaje == null || idViaje <= 0) return null;
    return idViaje;
  }

  Future<void> _presentDebitModal({
    required Future<DebitTripTransactionResult> Function() onDebit,
    bool esMultiple = false,
    int cantidadPasajes = 0,
  }) async {
    if (!mounted || _processingDebit) return;
    setState(() => _processingDebit = true);
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => DebitTransactionDialog(
          onDebit: onDebit,
          esMultiple: esMultiple,
          cantidadPasajes: cantidadPasajes,
        ),
      );
    } finally {
      if (mounted) setState(() => _processingDebit = false);
    }
  }

  Future<DebitTripTransactionResult> _debitFromCard({
    required int idViaje,
    required String uid,
    required String numeroSerieMonedero,
    required bool esQR,
    required bool esMultiple,
    required int cantidadPasajes,
  }) async {
    final wallet = await walletService.getWalletBySerie(
      numeroSerieMonedero.isNotEmpty ? numeroSerieMonedero : uid,
    );
    if (wallet == null) {
      return DebitTripTransactionResult(
        success: false,
        errorMessage:
            'Monedero no encontrado. Verifica que la tarjeta esté registrada.',
      );
    }

    return executeTripDebit(
      idViaje: idViaje,
      idCard: uid,
      numeroSerieMonedero: wallet.numeroSerie,
      esQR: esQR,
      esMultiple: esMultiple,
      cantidadPasajes: cantidadPasajes,
    );
  }

  Future<void> _ejecutarDebitoNfc(String uid) async {
    final idViaje = _idViajeActual();
    if (idViaje == null || _processingDebit) return;

    await _presentDebitModal(
      onDebit: () => _debitFromCard(
        idViaje: idViaje,
        uid: uid,
        numeroSerieMonedero: '',
        esQR: false,
        esMultiple: false,
        cantidadPasajes: 0,
      ),
    );
  }

  void _onQrDetect(BarcodeCapture capture) {
    if (!_puedeQr || _qrHandling || _processingDebit) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw == null || raw.trim().isEmpty) continue;
      _qrHandling = true;
      _ejecutarDebitoQr(raw.trim()).whenComplete(() {
        if (mounted) setState(() => _qrHandling = false);
      });
      return;
    }
  }

  Future<void> _ejecutarDebitoQr(String raw) async {
    final idViaje = _idViajeActual();
    if (idViaje == null || _processingDebit) return;

    final payload = parseQrDebitPayload(raw);
    if (!payload.isValid) {
      await _presentDebitModal(
        onDebit: () async => DebitTripTransactionResult(
          success: false,
          errorMessage: 'QR inválido: falta número de serie del monedero',
        ),
      );
      return;
    }

    if (payload.esMultiple && payload.cantidadPasajes > 1) {
      await speechService.announceMultipleTripCharge(payload.cantidadPasajes);
    }

    await _presentDebitModal(
      esMultiple: payload.esMultiple,
      cantidadPasajes: payload.cantidadPasajes,
      onDebit: () => _debitFromCard(
        idViaje: idViaje,
        uid: payload.idCard,
        numeroSerieMonedero: payload.numeroSerieMonedero,
        esQR: true,
        esMultiple: payload.esMultiple,
        cantidadPasajes: payload.cantidadPasajes,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cobro en viaje',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Con el viaje activo, acerca la tarjeta al lector '
              'o muestra el código QR frente a la cámara.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            if (_puedeNfcAuto) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _externalReaderAvailable == true && _nativeNfcEnabled != true
                        ? Icons.usb
                        : Icons.nfc,
                    color: _nativeNfcEnabled == false &&
                            _externalReaderAvailable == false
                        ? cs.error
                        : cs.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _nfcStatusText(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: _nativeNfcEnabled == false &&
                                    _externalReaderAvailable == false
                                ? cs.error
                                : cs.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            if (_puedeQr && _qrDisabled) ...[
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.qr_code_scanner, color: cs.error, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _cameraError ?? 'Escaneo QR no disponible.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.error,
                          ),
                    ),
                  ),
                ],
              ),
            ] else if (_puedeQr &&
                _qrHardwareChecked &&
                !_qrDisabled &&
                _qrController != null) ...[
              const SizedBox(height: 16),
              Text(
                'Código QR${_cameraFacing == CameraFacing.front ? ' (cámara frontal)' : ' (cámara trasera)'}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _qrController!,
                        onDetect: _onQrDetect,
                        errorBuilder: (context, error) {
                          _onScannerError(error);
                          return Center(
                            child: Text(
                              'Iniciando cámara…',
                              style: TextStyle(color: cs.onSurface),
                            ),
                          );
                        },
                      ),
                      Container(
                        alignment: Alignment.bottomCenter,
                        padding: const EdgeInsets.all(12),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              'Apunta al QR del pasajero',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              Text(
                'En web no hay NFC ni cámara QR; usa la app en el teléfono.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.error,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TurnActionButton extends StatefulWidget {
  final bool hasTurn;
  final bool hasViaje;

  const _TurnActionButton({required this.hasTurn, required this.hasViaje});

  @override
  State<_TurnActionButton> createState() => _TurnActionButtonState();
}

class _TurnActionButtonState extends State<_TurnActionButton> {
  bool _loading = false;

  Future<void> _onPressed() async {
    if (_loading || widget.hasViaje) return;
    setState(() => _loading = true);
    try {
      if (widget.hasTurn) {
        final ok = await turnService.endTurn();
        if (ok && mounted) auth.clearTurnIdInMemory();
      } else {
        final id = await turnService.startTurn();
        if (id != null && mounted) await auth.refreshTurnIdFromStorage();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.hasTurn ? 'Cerrar Turno' : 'Iniciar Turno';
    final disabled = widget.hasViaje; // No se puede cerrar/iniciar turno con viaje activo
    final isEnabled = !_loading && !disabled;
    return FilledButton.icon(
      onPressed: isEnabled ? _onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: isEnabled
            ? (widget.hasTurn ? Colors.red : const Color(0xFF2F855A)) // verde Iniciar / rojo Cerrar
            : Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(widget.hasTurn ? Icons.stop_circle_outlined : Icons.play_circle_outline),
      label: Text(label),
    );
  }
}

class _TripActionButton extends StatefulWidget {
  final bool hasViaje;
  final bool hasTurn;

  const _TripActionButton({required this.hasViaje, required this.hasTurn});

  @override
  State<_TripActionButton> createState() => _TripActionButtonState();
}

class _TripActionButtonState extends State<_TripActionButton> {
  bool _loading = false;

  Future<void> _onPressed() async {
    if (_loading) return;
    if (widget.hasViaje) {
      setState(() => _loading = true);
      try {
        final ok = await tripService.endTrip();
        if (ok && mounted) auth.clearViajeIdInMemory();
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    } else {
      if (!widget.hasTurn) return; // No iniciar viaje sin turno
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => const _StartTripModal(),
      );
      if (mounted) await auth.refreshViajeIdFromStorage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.hasViaje ? 'Cerrar viaje' : 'Iniciar Viaje';
    // Deshabilitado si no hay turno y no hay viaje activo (no se puede iniciar viaje sin turno)
    final disabled = !widget.hasViaje && !widget.hasTurn;
    final isEnabled = !_loading && !disabled;
    return FilledButton.icon(
      onPressed: isEnabled ? _onPressed : null,
      style: FilledButton.styleFrom(
        backgroundColor: isEnabled
            ? (widget.hasViaje ? Colors.red : const Color(0xFF1A87CC)) // Iniciar Viaje / Cerrar viaje
            : Colors.grey,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
      icon: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Icon(widget.hasViaje ? Icons.flag_outlined : Icons.directions_car_outlined),
      label: Text(label),
    );
  }
}

class _StartTripModal extends StatefulWidget {
  const _StartTripModal();

  @override
  State<_StartTripModal> createState() => _StartTripModalState();
}

class _StartTripModalState extends State<_StartTripModal> {
  List<Zone> _zones = [];
  List<Road> _roads = [];
  List<Variant> _variants = [];
  Zone? _selectedZone;
  Road? _selectedRoad;
  Variant? _selectedVariant;
  bool _loadingZones = true;
  bool _loadingRoads = false;
  bool _loadingVariants = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() {
      _loadingZones = true;
      _error = null;
      _zones = [];
      _roads = [];
      _variants = [];
      _selectedZone = null;
      _selectedRoad = null;
      _selectedVariant = null;
    });
    final list = await tripService.getZones();
    if (mounted) {
      setState(() {
        _zones = list;
        _loadingZones = false;
      });
    }
  }

  Future<void> _onZoneSelected(Zone? zone) async {
    setState(() {
      _selectedZone = zone;
      _selectedRoad = null;
      _selectedVariant = null;
      _roads = [];
      _variants = [];
      _error = null;
    });
    if (zone == null) return;
    setState(() => _loadingRoads = true);
    final list = await tripService.getRoadsByZone(zone.id);
    if (mounted) {
      setState(() {
        _roads = list;
        _loadingRoads = false;
      });
    }
  }

  Future<void> _onRoadSelected(Road? road) async {
    setState(() {
      _selectedRoad = road;
      _selectedVariant = null;
      _variants = [];
      _error = null;
    });
    if (road == null) return;
    setState(() => _loadingVariants = true);
    final list = await tripService.getVariantsByRoad(road.id);
    if (mounted) {
      setState(() {
        _variants = list;
        _loadingVariants = false;
      });
    }
  }

  Future<void> _confirm() async {
    final variant = _selectedVariant;
    if (variant == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final id = await tripService.startTrip(variant.id);
    if (!mounted) return;
    setState(() => _sending = false);
    if (id != null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = 'No se pudo iniciar el viaje');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Iniciar Viaje'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Zona
            const Text('Zona', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<Zone>(
              value: _selectedZone,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: Text(_loadingZones ? 'Cargando zonas...' : 'Selecciona zona'),
              items: _zones
                  .map((z) => DropdownMenuItem(value: z, child: Text(z.nombre)))
                  .toList(),
              onChanged: _loadingZones ? null : _onZoneSelected,
            ),
            const SizedBox(height: 16),
            // Ruta
            const Text('Ruta', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<Road>(
              value: _selectedRoad,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: Text(
                _selectedZone == null
                    ? 'Selecciona primero una zona'
                    : _loadingRoads
                        ? 'Cargando rutas...'
                        : 'Selecciona ruta',
              ),
              items: _roads
                  .map((r) => DropdownMenuItem(value: r, child: Text(r.nombre)))
                  .toList(),
              onChanged: (_selectedZone == null || _loadingRoads) ? null : _onRoadSelected,
            ),
            const SizedBox(height: 16),
            // Variante
            const Text('Variante', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            DropdownButtonFormField<Variant>(
              value: _selectedVariant,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              hint: Text(
                _selectedRoad == null
                    ? 'Selecciona primero una ruta'
                    : _loadingVariants
                        ? 'Cargando variantes...'
                        : 'Selecciona variante',
              ),
              items: _variants
                  .map((v) => DropdownMenuItem(value: v, child: Text(v.nombre)))
                  .toList(),
              onChanged: (_selectedRoad == null || _loadingVariants)
                  ? null
                  : (Variant? v) => setState(() => _selectedVariant = v),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_sending || _selectedVariant == null) ? null : _confirm,
          child: _sending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Iniciar'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          // TODO: Implementar navegación
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
