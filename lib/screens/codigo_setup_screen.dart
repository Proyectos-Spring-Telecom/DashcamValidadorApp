import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../app/auth.dart';
import '../services/codigo_service.dart';
import '../config/app_config.dart';

class CodigoSetupScreen extends StatefulWidget {
  const CodigoSetupScreen({super.key});

  @override
  State<CodigoSetupScreen> createState() => _CodigoSetupScreenState();
}

class _CodigoSetupScreenState extends State<CodigoSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codigoController = TextEditingController();
  final _confirmCodigoController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscureCodigo = true;
  bool _obscureConfirmCodigo = true;
  String? _errorMessage;
  
  // Opciones de longitud de código
  int _selectedCodigoLength = AppConfig.defaultCodigoLength;
  final List<int> _codigoLengthOptions = AppConfig.allowedCodigoLengths;

  @override
  void dispose() {
    _codigoController.dispose();
    _confirmCodigoController.dispose();
    super.dispose();
  }

  String? _validateCodigo(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu código';
    }
    
    if (!CodigoService.isValidCodigo(value, requiredLength: _selectedCodigoLength)) {
      if (value.length != _selectedCodigoLength) {
        return 'El código debe tener $_selectedCodigoLength dígitos';
      }
      return 'El código solo puede contener números';
    }
    
    return null;
  }

  String? _validateConfirmCodigo(String? value) {
    final codigoValidation = _validateCodigo(value);
    if (codigoValidation != null) return codigoValidation;
    
    if (value != _codigoController.text) {
      return 'Los códigos no coinciden';
    }
    
    return null;
  }

  Future<void> _setupCodigo() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await codigoService.updateOperatorCodigo(
        userName: auth.loginResponse!.userName,
        codigo: _codigoController.text,
      );

      if (!mounted) return;

      if (success) {
        // Mostrar mensaje de éxito
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Código configurado exitosamente'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            duration: const Duration(seconds: 2),
          ),
        );
        
        // Regresar a configuración
        context.pop();
      } else {
        setState(() {
          _errorMessage = CodigoService.lastError ?? 'Error al configurar código';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error inesperado: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Código'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icono y descripción
              Icon(
                Icons.security,
                size: 64,
                color: cs.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Configurar Código de Seguridad',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Establece un código para mayor seguridad en tu cuenta',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              
              // Selección de longitud de código
              Text(
                'Longitud del código',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: _codigoLengthOptions.map((length) {
                  return ButtonSegment<int>(
                    value: length,
                    label: Text('$length dígitos'),
                  );
                }).toList(),
                selected: {_selectedCodigoLength},
                onSelectionChanged: (Set<int> selected) {
                  setState(() {
                    _selectedCodigoLength = selected.first;
                    // Limpiar campos cuando cambie la longitud
                    _codigoController.clear();
                    _confirmCodigoController.clear();
                    _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 24),

              // Campo código
              TextFormField(
                controller: _codigoController,
                obscureText: _obscureCodigo,
                keyboardType: TextInputType.number,
                maxLength: _selectedCodigoLength,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_selectedCodigoLength),
                ],
                decoration: InputDecoration(
                  labelText: 'Código ($_selectedCodigoLength dígitos)',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureCodigo = !_obscureCodigo),
                    icon: Icon(_obscureCodigo ? Icons.visibility : Icons.visibility_off),
                  ),
                  helperText: 'Solo números, $_selectedCodigoLength dígitos',
                ),
                validator: _validateCodigo,
                onChanged: (value) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Campo confirmar código
              TextFormField(
                controller: _confirmCodigoController,
                obscureText: _obscureConfirmCodigo,
                keyboardType: TextInputType.number,
                maxLength: _selectedCodigoLength,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(_selectedCodigoLength),
                ],
                decoration: InputDecoration(
                  labelText: 'Confirmar código',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscureConfirmCodigo = !_obscureConfirmCodigo),
                    icon: Icon(_obscureConfirmCodigo ? Icons.visibility : Icons.visibility_off),
                  ),
                  helperText: 'Repite el mismo código',
                ),
                validator: _validateConfirmCodigo,
                onChanged: (value) {
                  if (_errorMessage != null) {
                    setState(() => _errorMessage = null);
                  }
                },
              ),
              const SizedBox(height: 24),

              // Mensaje de error
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: cs.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: cs.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_errorMessage != null) const SizedBox(height: 16),

              // Botón configurar
              FilledButton(
                onPressed: _isLoading ? null : _setupCodigo,
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Configurar Código'),
              ),
              const SizedBox(height: 16),

              // Información adicional
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Información importante',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: cs.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• El código debe tener exactamente $_selectedCodigoLength dígitos\n'
                      '• Solo se permiten números (0-9)\n'
                      '• Debes confirmar el código ingresándolo dos veces\n'
                      '• El código se almacena de forma segura en el servidor',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

