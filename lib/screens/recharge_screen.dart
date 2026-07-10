import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../config/app_config.dart';
import '../services/nfc_service.dart';
import '../services/wallet_service.dart';
import '../services/native_gps_service.dart';
import '../utils/logger.dart';

class RechargeScreen extends StatefulWidget {
  const RechargeScreen({super.key});

  @override
  State<RechargeScreen> createState() => _RechargeScreenState();
}

class _RechargeScreenState extends State<RechargeScreen> {
  final TextEditingController _amountController = TextEditingController();
  static const List<double> _suggestedAmounts = [20, 50, 100, 200];
  double? _selectedSuggestedAmount;
  bool _isProcessing = false;
  String? _statusMessage;
  String? _cardSerie;
  MonederoInfo? _wallet;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _onNumberPressed(String number) {
    final currentText = _amountController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (currentText.length < 6) { // Limitar a 6 dígitos
      setState(() {
        _amountController.text = currentText + number;
        _selectedSuggestedAmount = null;
      });
    }
  }

  void _onBackspacePressed() {
    final currentText = _amountController.text.replaceAll(RegExp(r'[^\d]'), '');
    if (currentText.isNotEmpty) {
      setState(() {
        _amountController.text = currentText.substring(0, currentText.length - 1);
        _selectedSuggestedAmount = null;
      });
    }
  }

  void _onSuggestedAmountPressed(double amount) {
    setState(() {
      _selectedSuggestedAmount = amount;
      _amountController.text = amount.toStringAsFixed(0);
    });
  }

  void _clearAmount() {
    setState(() {
      _amountController.clear();
      _selectedSuggestedAmount = null;
    });
  }

  String _formatAmount(String text) {
    if (text.isEmpty) return '\$0.00';
    final amount = double.tryParse(text) ?? 0.0;
    return '\$${amount.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amount = _amountController.text.isEmpty 
        ? 0.0 
        : double.tryParse(_amountController.text) ?? 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recargar Monedero'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Sección superior: Monto ingresado
            Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text(
                    'Monto a recargar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F855A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: cs.outline.withOpacity(0.2),
                        width: 2,
                      ),
                    ),
                    child: Text(
                      _formatAmount(_amountController.text),
                      style: Theme.of(context).textTheme.displayMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                    ),
                  ),
                  if (_statusMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isProcessing 
                            ? cs.primaryContainer.withOpacity(0.3)
                            : cs.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isProcessing)
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                              ),
                            ),
                          if (_isProcessing) const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _statusMessage!,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Botones de cantidades sugeridas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cantidades sugeridas',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: _suggestedAmounts.map((suggestedAmount) {
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: suggestedAmount != _suggestedAmounts.last ? 12 : 0,
                          ),
                          child: FilledButton(
                            onPressed: () => _onSuggestedAmountPressed(suggestedAmount),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF2F855A),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              '\$${suggestedAmount.toStringAsFixed(0)}',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Panel numérico
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Fila 1-3
                    Row(
                      children: [
                        Expanded(child: _buildKey('1', () => _onNumberPressed('1'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('2', () => _onNumberPressed('2'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('3', () => _onNumberPressed('3'))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Fila 4-6
                    Row(
                      children: [
                        Expanded(child: _buildKey('4', () => _onNumberPressed('4'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('5', () => _onNumberPressed('5'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('6', () => _onNumberPressed('6'))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Fila 7-9
                    Row(
                      children: [
                        Expanded(child: _buildKey('7', () => _onNumberPressed('7'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('8', () => _onNumberPressed('8'))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildKey('9', () => _onNumberPressed('9'))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Fila 0 y borrar
                    Row(
                      children: [
                        Expanded(child: _buildKey('0', () => _onNumberPressed('0'))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildKey('', _onBackspacePressed, isBackspace: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Botón de acción (por ahora solo diseño)
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
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (amount > 0 && !_isProcessing) ? _processRecharge : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F855A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isProcessing
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Procesando...',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ],
                          )
                        : Text(
                            'Recargar',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKey(String label, VoidCallback onPressed, {bool isBackspace = false}) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: cs.outline.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Center(
            child: isBackspace
                ? Icon(Icons.backspace_outlined, color: cs.onSurface)
                : Text(
                    label,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                  ),
          ),
        ),
      ),
    );
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

  Future<void> _processRecharge() async {
    final amount = _amountController.text.isEmpty 
        ? 0.0 
        : double.tryParse(_amountController.text) ?? 0.0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa un monto válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _statusMessage = 'Acerca la tarjeta al lector (10 segundos)...';
      _cardSerie = null;
      _wallet = null;
      _isProcessing = true;
    });

    final uid = await _readCardUidWithTimeout();
    if (!mounted) return;

    if (uid == null) {
      setState(() {
        _statusMessage = 'No se detectó tarjeta. Intenta nuevamente.';
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se detectó tarjeta. Intenta nuevamente.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _cardSerie = uid;
      _statusMessage = 'Consultando monedero...';
    });

    final wallet = await walletService.getWalletBySerie(uid);
    if (!mounted) return;

    if (wallet == null) {
      setState(() {
        _statusMessage = 'No se pudo obtener el monedero. Verifica la tarjeta.';
        _isProcessing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener el monedero. Verifica la tarjeta.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _wallet = wallet;
      _statusMessage = 'Obteniendo ubicación GPS...';
    });

    final location = await nativeGpsService.getCurrentLocation();
    if (!mounted) return;
    final lat = location?.lat ?? 19.432608;
    final lon = location?.lon ?? -99.133209;

    setState(() => _statusMessage = 'Procesando recarga...');

    appLogger.i('💰 Iniciando recarga de \$${amount.toStringAsFixed(2)} para monedero ${wallet.numeroSerie}');
    
    final result = await walletService.rechargeWallet(
      numeroSerieMonedero: wallet.numeroSerie,
      monto: amount,
      latitudInicial: lat,
      longitudInicial: lon,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isProcessing = false;
      });
      
      // Mostrar modal de éxito
      _showSuccessDialog(context, amount, wallet.saldo + amount);
    } else {
      setState(() {
        _statusMessage = '❌ Error: ${result.errorMessage ?? "No se pudo procesar la recarga"}';
        _isProcessing = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error: ${result.errorMessage ?? "No se pudo procesar la recarga"}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Muestra un diálogo de éxito y regresa a la vista principal
  void _showSuccessDialog(BuildContext context, double amount, double newBalance) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _RechargeSuccessDialog(
        amount: amount,
        newBalance: newBalance,
        onClose: () {
          // Regresar a la vista principal
          if (mounted) {
            context.go('/home');
          }
        },
      ),
    );
  }
}

/// Diálogo de éxito para recarga
class _RechargeSuccessDialog extends StatefulWidget {
  final double amount;
  final double newBalance;
  final VoidCallback onClose;

  const _RechargeSuccessDialog({
    required this.amount,
    required this.newBalance,
    required this.onClose,
  });

  @override
  State<_RechargeSuccessDialog> createState() => _RechargeSuccessDialogState();
}

class _RechargeSuccessDialogState extends State<_RechargeSuccessDialog> {
  double _countdown = 3.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    // Timer para cerrar el diálogo y regresar después de 3 segundos
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          _countdown = (_countdown - 0.1).clamp(0.0, 3.0);
        });
        
        if (_countdown <= 0) {
          timer.cancel();
          if (mounted) {
            Navigator.of(context).pop();
            widget.onClose();
          }
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icono de éxito
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 50,
              ),
            ),
            const SizedBox(height: 20),
            
            // Mensaje de éxito
            Text(
              '✅ Transacción Exitosa',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            // Detalles de la recarga
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Monto recargado:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        '\$${widget.amount.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Nuevo saldo:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        '\$${widget.newBalance.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // Contador
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.blue,
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  _countdown > 0 ? _countdown.ceil().toString() : '0',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Mensaje
            Text(
              _countdown > 0
                  ? 'Regresando en ${_countdown.ceil()} segundo${_countdown.ceil() == 1 ? '' : 's'}...'
                  : 'Regresando...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
