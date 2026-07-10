import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/auth.dart';
import '../services/nfc_service.dart';
import '../services/wallet_service.dart';
import '../services/speech_service.dart';
import '../services/trip_debit_coordinator.dart';
import '../utils/logger.dart';
import '../utils/qr_debit_parser.dart';
import 'qr_scan_debit_screen.dart';

class DirectoScreen extends StatefulWidget {
  const DirectoScreen({super.key});

  @override
  State<DirectoScreen> createState() => _DirectoScreenState();
}

class _DirectoScreenState extends State<DirectoScreen> {
  static const List<double> _amounts = [5, 10, 15, 20, 25, 50, 80, 100];

  double? _selectedAmount;
  bool _isProcessing = false;
  String? _statusMessage;
  String? _cardSerie;
  MonederoInfo? _wallet;
  PassengerInfo? _passenger;

  bool get _puedeQr =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _onAmountSelected(double amount) {
    setState(() {
      _selectedAmount = amount;
      _statusMessage =
          'Monto \$${amount.toStringAsFixed(0)} seleccionado. Pulsa Cobrar con NFC o Escanear QR.';
      _cardSerie = null;
      _wallet = null;
      _passenger = null;
    });
  }

  void _snack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.orange),
    );
  }

  Future<void> _startNfcCobro() async {
    final idViajeSesion = int.tryParse(auth.idViaje ?? '');
    if (idViajeSesion == null || idViajeSesion <= 0) {
      _snack('Inicia un viaje en la pestaña Inicio antes de cobrar.');
      return;
    }
    final amount = _selectedAmount;
    if (amount == null) {
      _snack('Selecciona un monto en la cuadrícula.');
      return;
    }

    setState(() {
      _statusMessage = 'Acerca la tarjeta al lector...';
      _cardSerie = null;
      _wallet = null;
      _passenger = null;
    });

    final uid = await _readCardUidWithTimeout();
    if (!mounted) return;

    if (uid == null) {
      setState(() => _statusMessage = 'No se detectó tarjeta. Intenta nuevamente.');
      return;
    }

    setState(() {
      _cardSerie = uid;
      _statusMessage = 'Consultando monedero...';
      _isProcessing = true;
    });

    final wallet = await walletService.getWalletBySerie(uid);
    if (!mounted) return;

    if (wallet == null) {
      setState(() {
        _statusMessage = 'No se pudo obtener el monedero. Verifica la tarjeta.';
        _isProcessing = false;
      });
      return;
    }

    PassengerInfo? passenger;
    // Validar que idPasajero no sea null y sea mayor que 0 (el backend devuelve 0 cuando no hay pasajero)
    if (wallet.idPasajero != null && wallet.idPasajero! > 0) {
      appLogger.d('Monedero tiene idPasajero: ${wallet.idPasajero}, obteniendo información del pasajero...');
      passenger = await walletService.getPassengerById(wallet.idPasajero!);
      if (passenger != null) {
        appLogger.i('✅ Información del pasajero obtenida: ${passenger.nombreCompleto}');
      } else {
        appLogger.w('⚠️ No se pudo obtener información del pasajero con id: ${wallet.idPasajero}');
      }
    } else {
      appLogger.d('Monedero no tiene idPasajero asociado (idPasajero: ${wallet.idPasajero})');
    }

    setState(() {
      _wallet = wallet;
      _passenger = passenger;
      _statusMessage = 'Saldo actual: \$${wallet.saldo.toStringAsFixed(2)}';
    });

    if (wallet.saldo < amount) {
      setState(() {
        _statusMessage = 'Saldo insuficiente. Saldo actual \$${wallet.saldo.toStringAsFixed(2)}';
        _isProcessing = false;
      });
      appLogger.w('⚠️ Saldo insuficiente: ${wallet.saldo} < $amount');
      return;
    }

    appLogger.i('💰 Saldo suficiente (${wallet.saldo} >= $amount), iniciando débito...');
    final debitResult = await _debitTripTransaction(wallet, uid);
    appLogger.i('💰 Resultado del débito: ${debitResult.success ? "ÉXITO" : "FALLO"}');
    if (!mounted) return;

    if (debitResult.success) {
      final nuevoSaldo = wallet.saldo - amount;
      // Preservar la información del pasajero antes de actualizar el estado
      // Usar la variable local 'passenger' que se obtuvo antes del débito
      final passengerToKeep = passenger ?? _passenger;
      appLogger.d('Preservando información del pasajero después del débito: ${passengerToKeep?.nombreCompleto ?? "ninguno"}');
      appLogger.d('Valores antes de setState - wallet.idPasajero: ${wallet.idPasajero}, passengerToKeep: ${passengerToKeep?.nombreCompleto ?? "null"}');
      
      setState(() {
        _wallet = MonederoInfo(
          id: wallet.id,
          numeroSerie: wallet.numeroSerie,
          saldo: nuevoSaldo,
          fechaActivacion: wallet.fechaActivacion,
          fechaCreacion: wallet.fechaCreacion,
          fechaActualizacion: wallet.fechaActualizacion,
          estatus: wallet.estatus,
          idPasajero: wallet.idPasajero, // Preservar idPasajero
          idCliente: wallet.idCliente,
          idTipoPasajero: wallet.idTipoPasajero,
        );
        // Preservar la información del pasajero que ya se obtuvo
        _passenger = passengerToKeep;
        _statusMessage = 'Débito exitoso. Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}';
      });
      
      // Log después del setState para verificar
      appLogger.d('Estado después del débito - idPasajero: ${_wallet?.idPasajero}, passenger: ${_passenger?.nombreCompleto ?? "null"}');
    } else {
      setState(() {
        _statusMessage =
            debitResult.errorMessage ?? 'No se pudo realizar el débito. Intenta nuevamente.';
      });
    }

    setState(() => _isProcessing = false);
  }

  Future<void> _startQrCobro() async {
    if (!_puedeQr) {
      _snack('Escanear QR solo está disponible en Android o iOS.');
      return;
    }
    final idViajeSesion = int.tryParse(auth.idViaje ?? '');
    if (idViajeSesion == null || idViajeSesion <= 0) {
      _snack('Inicia un viaje en la pestaña Inicio antes de cobrar.');
      return;
    }
    final amount = _selectedAmount;
    if (amount == null) {
      _snack('Selecciona un monto en la cuadrícula.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _cardSerie = null;
      _wallet = null;
      _passenger = null;
      _statusMessage = 'Escanea el código QR...';
    });

    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanDebitScreen()),
    );
    if (!mounted) return;

    if (raw == null || raw.isEmpty) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Escaneo cancelado o sin datos.';
      });
      return;
    }

    final payload = parseQrDebitPayload(raw);
    if (!payload.isValid) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'QR inválido: falta número de serie del monedero.';
      });
      return;
    }

    setState(() {
      _statusMessage = 'Consultando monedero...';
      _cardSerie = payload.numeroSerieMonedero;
    });

    final wallet = await walletService.getWalletBySerie(payload.numeroSerieMonedero);
    if (!mounted) return;

    if (wallet == null) {
      setState(() {
        _statusMessage = 'No se pudo obtener el monedero. Verifica el QR.';
        _isProcessing = false;
      });
      return;
    }

    PassengerInfo? passenger;
    if (wallet.idPasajero != null && wallet.idPasajero! > 0) {
      passenger = await walletService.getPassengerById(wallet.idPasajero!);
    }

    setState(() {
      _wallet = wallet;
      _passenger = passenger;
      _statusMessage = 'Saldo actual: \$${wallet.saldo.toStringAsFixed(2)}';
    });

    if (wallet.saldo < amount) {
      setState(() {
        _statusMessage =
            'Saldo insuficiente. Saldo actual \$${wallet.saldo.toStringAsFixed(2)}';
        _isProcessing = false;
      });
      return;
    }

    if (payload.esMultiple && payload.cantidadPasajes > 1) {
      await speechService.announceMultipleTripCharge(payload.cantidadPasajes);
    }

    setState(() => _statusMessage = 'Procesando cobro por QR...');
    final debitResult = await executeTripDebit(
      idViaje: idViajeSesion,
      idCard: payload.idCard,
      numeroSerieMonedero: payload.numeroSerieMonedero,
      esQR: true,
      esMultiple: payload.esMultiple,
      cantidadPasajes: payload.cantidadPasajes,
    );
    if (!mounted) return;

    if (debitResult.success) {
      if (payload.esMultiple && payload.cantidadPasajes > 1) {
        await speechService.announceMultipleTripChargeSuccess(
          payload.cantidadPasajes,
        );
      }
      if (!mounted) return;
      final nuevoSaldo = wallet.saldo - amount;
      final passengerToKeep = passenger ?? _passenger;
      setState(() {
        _wallet = MonederoInfo(
          id: wallet.id,
          numeroSerie: wallet.numeroSerie,
          saldo: nuevoSaldo,
          fechaActivacion: wallet.fechaActivacion,
          fechaCreacion: wallet.fechaCreacion,
          fechaActualizacion: wallet.fechaActualizacion,
          estatus: wallet.estatus,
          idPasajero: wallet.idPasajero,
          idCliente: wallet.idCliente,
          idTipoPasajero: wallet.idTipoPasajero,
        );
        _passenger = passengerToKeep;
        _statusMessage =
            'Débito QR exitoso. Nuevo saldo: \$${nuevoSaldo.toStringAsFixed(2)}';
      });
    } else {
      setState(() {
        _statusMessage = debitResult.errorMessage ??
            'No se pudo realizar el débito. Intenta nuevamente.';
      });
    }

    setState(() => _isProcessing = false);
  }

  Future<String?> _readCardUidWithTimeout() => NfcService.readCardUidWithTimeout();

  Future<DebitTripTransactionResult> _debitTripTransaction(
    MonederoInfo wallet,
    String idCard,
  ) async {
    if (!mounted) {
      return DebitTripTransactionResult(success: false, errorMessage: 'Sin contexto');
    }
    setState(() => _statusMessage = 'Procesando cobro...');

    final idViaje = int.tryParse(auth.idViaje ?? '');
    if (idViaje == null || idViaje <= 0) {
      return DebitTripTransactionResult(
        success: false,
        errorMessage: 'No hay viaje activo en la sesión.',
      );
    }

    appLogger.i(
        '💳 Débito NFC monedero ${wallet.numeroSerie}, idCard=$idCard, idViaje=$idViaje');
    return executeTripDebit(
      idViaje: idViaje,
      idCard: idCard,
      numeroSerieMonedero: wallet.numeroSerie,
      esQR: false,
      esMultiple: false,
      cantidadPasajes: 0,
    );
  }

  /// Obtiene el color del card de estado según el mensaje actual
  Color _getStatusColor(ColorScheme cs) {
    final message = _statusMessage?.toLowerCase() ?? '';
    if (message.contains('éxito') || message.contains('exitoso') || message.contains('completado')) {
      return Colors.green.shade50;
    } else if (message.contains('error') || message.contains('fallo') || message.contains('no se pudo')) {
      return Colors.red.shade50;
    } else if (message.contains('procesando') || message.contains('debitando') || message.contains('consultando')) {
      return Colors.blue.shade50;
    } else if (message.contains('insuficiente')) {
      return Colors.orange.shade50;
    } else if (message.contains('acerca') || message.contains('tarjeta')) {
      return Colors.amber.shade50;
    }
    return cs.surfaceContainerHighest;
  }

  /// Obtiene el color del texto según el estado
  Color _getStatusTextColor(ColorScheme cs) {
    final message = _statusMessage?.toLowerCase() ?? '';
    if (message.contains('éxito') || message.contains('exitoso') || message.contains('completado')) {
      return Colors.green.shade900;
    } else if (message.contains('error') || message.contains('fallo') || message.contains('no se pudo')) {
      return Colors.red.shade900;
    } else if (message.contains('procesando') || message.contains('debitando') || message.contains('consultando')) {
      return Colors.blue.shade900;
    } else if (message.contains('insuficiente')) {
      return Colors.orange.shade900;
    } else if (message.contains('acerca') || message.contains('tarjeta')) {
      return Colors.amber.shade900;
    }
    return cs.onSurface;
  }

  /// Obtiene el color del ícono según el estado
  Color _getStatusIconColor(ColorScheme cs) {
    final message = _statusMessage?.toLowerCase() ?? '';
    if (message.contains('éxito') || message.contains('exitoso') || message.contains('completado')) {
      return Colors.green.shade700;
    } else if (message.contains('error') || message.contains('fallo') || message.contains('no se pudo')) {
      return Colors.red.shade700;
    } else if (message.contains('procesando') || message.contains('debitando') || message.contains('consultando')) {
      return Colors.blue.shade700;
    } else if (message.contains('insuficiente')) {
      return Colors.orange.shade700;
    } else if (message.contains('acerca') || message.contains('tarjeta')) {
      return Colors.amber.shade700;
    }
    return cs.primary;
  }

  /// Obtiene el ícono según el estado
  IconData _getStatusIcon() {
    final message = _statusMessage?.toLowerCase() ?? '';
    if (message.contains('éxito') || message.contains('exitoso') || message.contains('completado')) {
      return Icons.check_circle;
    } else if (message.contains('error') || message.contains('fallo') || message.contains('no se pudo')) {
      return Icons.error;
    } else if (message.contains('procesando') || message.contains('debitando') || message.contains('consultando')) {
      return Icons.hourglass_empty;
    } else if (message.contains('insuficiente')) {
      return Icons.warning;
    } else if (message.contains('acerca') || message.contains('tarjeta')) {
      return Icons.nfc;
    }
    return Icons.info;
  }

  /// Construye una fila de información con label y valor
  Widget _buildInfoRow(String label, String value, ColorScheme cs, {bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withOpacity(0.7),
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontSize: isHighlight ? 20 : 16,
                  fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
                  color: isHighlight ? cs.primary : cs.onSurface,
                ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Debug: Log para verificar estado antes de renderizar
    if (_wallet != null) {
      appLogger.d('🔍 Build - wallet.idPasajero: ${_wallet!.idPasajero}, passenger: ${_passenger?.nombreCompleto ?? "null"}');
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Débito directo'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Regresar',
          onPressed: () {
            // Intentar regresar con pop, si no hay historial, ir al home
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Column(
        children: [
          // Card de estado arriba - más grande y visible
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Card de estado principal con colores según el estado
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _getStatusColor(cs),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _getStatusColor(cs).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getStatusIcon(),
                              color: _getStatusIconColor(cs),
                              size: 32,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Estado',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusTextColor(cs),
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _statusMessage ??
                              'Selecciona un monto y luego Cobrar con NFC o Escanear QR.',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: _getStatusTextColor(cs),
                                height: 1.3,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (_cardSerie != null) ...[
                    const SizedBox(height: 20),
                    // Card de monedero - más grande y visible
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.primary.withOpacity(0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_wallet, color: cs.primary, size: 28),
                              const SizedBox(width: 12),
                              Text(
                                'Monedero',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow('Serie', _cardSerie!, cs),
                          if (_wallet != null) ...[
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              'Saldo',
                              '\$${_wallet!.saldo.toStringAsFixed(2)}',
                              cs,
                              isHighlight: true,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow('Estatus', _wallet!.estatus.toString(), cs),
                          ],
                        ],
                      ),
                    ),
                    // Mostrar card de pasajero solo si hay relación (idPasajero no es null, > 0, y passenger existe)
                    if (_wallet != null && 
                        _wallet!.idPasajero != null && 
                        _wallet!.idPasajero! > 0 && 
                        _passenger != null) ...[
                      const SizedBox(height: 20),
                      // Card de pasajero - más grande y visible
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: cs.secondary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.person, color: cs.secondary, size: 28),
                                const SizedBox(width: 12),
                                Text(
                                  'Pasajero',
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: cs.onSecondaryContainer,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _passenger!.nombreCompleto,
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSecondaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          // Botones grandes y cuadrados en el pie de página
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selecciona un monto:',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0, // Botones cuadrados
                    children: _amounts
                        .map(
                          (amount) => FilledButton.tonal(
                            onPressed: _isProcessing
                                ? null
                                : () => _onAmountSelected(amount),
                            style: FilledButton.styleFrom(
                              backgroundColor: _selectedAmount == amount
                                  ? cs.primaryContainer
                                  : cs.surfaceVariant,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              padding: const EdgeInsets.all(16),
                            ),
                            child: Text(
                              '\$${amount.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_isProcessing || _selectedAmount == null)
                              ? null
                              : _startNfcCobro,
                          icon: const Icon(Icons.nfc),
                          label: const Text('Cobrar con NFC'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0A2E57),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_isProcessing ||
                                  _selectedAmount == null ||
                                  !_puedeQr)
                              ? null
                              : _startQrCobro,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Escanear QR'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2F855A),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

