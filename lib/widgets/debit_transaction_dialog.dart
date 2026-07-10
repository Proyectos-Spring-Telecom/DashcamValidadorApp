import 'dart:async';

import 'package:flutter/material.dart';

import '../services/wallet_service.dart';
import '../services/speech_service.dart';
import '../utils/nfc_result_codes.dart';

enum _DebitDialogPhase { processing, success, failure }

/// Modal de espera → confirmación o rechazo del cobro (/transacciones/debito).
class DebitTransactionDialog extends StatefulWidget {
  final Future<DebitTripTransactionResult> Function() onDebit;
  final bool esMultiple;
  final int cantidadPasajes;

  const DebitTransactionDialog({
    super.key,
    required this.onDebit,
    this.esMultiple = false,
    this.cantidadPasajes = 0,
  });

  @override
  State<DebitTransactionDialog> createState() => _DebitTransactionDialogState();
}

class _DebitTransactionDialogState extends State<DebitTransactionDialog> {
  _DebitDialogPhase _phase = _DebitDialogPhase.processing;
  String? _errorMessage;
  Timer? _autoCloseTimer;

  @override
  void initState() {
    super.initState();
    _execute();
  }

  Future<void> _execute() async {
    try {
      final result = await widget.onDebit();
      if (!mounted) return;
      if (result.success) {
        if (widget.esMultiple && widget.cantidadPasajes > 1) {
          await speechService.announceMultipleTripChargeSuccess(
            widget.cantidadPasajes,
          );
        }
        if (!mounted) return;
        setState(() => _phase = _DebitDialogPhase.success);
        _autoCloseTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) Navigator.of(context).pop();
        });
      } else {
        setState(() {
          _phase = _DebitDialogPhase.failure;
          _errorMessage = NfcResultCodes.friendlyMessage(
            result.errorMessage ?? 'No se pudo completar el cobro',
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _DebitDialogPhase.failure;
        _errorMessage = 'Error inesperado al procesar el cobro';
      });
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _DebitDialogPhase.processing,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            child: switch (_phase) {
              _DebitDialogPhase.processing => _buildProcessing(context),
              _DebitDialogPhase.success => _buildSuccess(context),
              _DebitDialogPhase.failure => _buildFailure(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildProcessing(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 72,
          height: 72,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
        const SizedBox(height: 28),
        Text(
          'Procesando cobro',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'Espera mientras se realiza la transacción…',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.green.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_circle, color: Colors.green.shade700, size: 64),
        ),
        const SizedBox(height: 24),
        Text(
          'Cobro exitoso',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Cerrando…',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildFailure(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.cancel, color: Colors.red.shade700, size: 64),
        ),
        const SizedBox(height: 24),
        Text(
          'Cobro rechazado',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade800,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          _errorMessage ?? 'No se pudo completar el cobro',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
