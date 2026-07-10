import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../app/auth.dart';
import '../config/app_config.dart';
import '../services/storage_service.dart';

enum LoginMode { password, codigo }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _codigoCtrl = TextEditingController();
  final StorageService _storage = StorageService();

  bool _loading = false;
  String _loadingMessage = 'Iniciando sesión...';
  bool _obscurePassword = true;
  bool _obscureCodigo = true;
  bool _hasStoredCodigo = false;
  bool _initializing = true;
  String? _storedUserName;
  LoginMode _mode = LoginMode.password;

  @override
  void initState() {
    super.initState();
    _codigoCtrl.addListener(() {
      setState(() {}); // Actualizar UI cuando cambie el texto
    });
    _loadStoredPreferences();
  }

  Future<void> _loadStoredPreferences() async {
    final storedName = await _storage.getUserName();
    final hasCodigo = await _storage.getCodigoStatus();

    setState(() {
      _storedUserName = storedName;
      _hasStoredCodigo = hasCodigo;
      _mode = hasCodigo ? LoginMode.codigo : LoginMode.password;
      if (storedName != null && storedName.isNotEmpty) {
        _userCtrl.text = storedName;
      }
      _initializing = false;
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    _codigoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loginWithPassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _loadingMessage = 'Verificando credenciales...';
    });

    await Future.delayed(const Duration(milliseconds: 400));

    final ok = await auth.login(_userCtrl.text.trim(), _passCtrl.text);

    if (!mounted) return;
    setState(() => _loading = false);

    _handleLoginResult(ok);
  }

  Future<void> _loginWithCodigo() async {
    if (!_pinFormKey.currentState!.validate()) return;
    if ((_storedUserName ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay usuario guardado para usar código. Inicia con tu contraseña.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _loadingMessage = 'Validando código...';
    });

    final ok = await auth.loginWithCodigo(_codigoCtrl.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    _handleLoginResult(ok);
  }

  void _handleLoginResult(bool ok) {
    if (ok) {
      final nombreCompleto = auth.nombreCompleto ?? 'Usuario';
      final deviceId = auth.lastDeviceValidadorId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deviceId == null || deviceId.isEmpty
                ? '¡Bienvenido, $nombreCompleto!'
                : '¡Bienvenido, $nombreCompleto!\nDevice ID: $deviceId',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          duration: const Duration(seconds: 6),
        ),
      );
      context.go('/home');
    } else {
      final errorMsg = auth.errorMessage ?? 'Error al iniciar sesión';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _onModeChanged(LoginMode mode) {
    if (mode == LoginMode.codigo && (_storedUserName == null || _storedUserName!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Para usar código inicia sesión con tu contraseña primero.'),
        ),
      );
      return;
    }
    setState(() => _mode = mode);
  }

  /// Borra el correo/código guardados para permitir login de otro operador.
  Future<void> _useAnotherAccount() async {
    await auth.clearStoredOperatorForOtherUser();
    if (!mounted) return;
    setState(() {
      _storedUserName = null;
      _hasStoredCodigo = false;
      _mode = LoginMode.password;
      _userCtrl.clear();
      _passCtrl.clear();
      _codigoCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Inicia sesión con el usuario y contraseña de la otra cuenta.'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String? _validateCodigo(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu código';
    }
    if (!AppConfig.allowedCodigoLengths.contains(value.length)) {
      return 'El código debe tener ${AppConfig.allowedCodigoLengths.join(" o ")} dígitos';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_initializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.png',
                    width: 192,
                    height: 192,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.directions_bus, color: cs.primary, size: 48);
                    },
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Iniciar Sesión',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<LoginMode>(
                    segments: const [
                      ButtonSegment(
                        value: LoginMode.password,
                        label: Text('Contraseña'),
                        icon: Icon(Icons.lock_outline),
                      ),
                      ButtonSegment(
                        value: LoginMode.codigo,
                        label: Text('Código'),
                        icon: Icon(Icons.lock),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (selection) => _onModeChanged(selection.first),
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _mode == LoginMode.password
                        ? _buildPasswordForm(context)
                        : _buildCodigoForm(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm(BuildContext context) {
    return Form(
      key: _passwordFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _userCtrl,
            decoration: const InputDecoration(
              labelText: 'Usuario o correo',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu usuario' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passCtrl,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              ),
            ),
            validator: (v) => (v == null || v.isEmpty) ? 'Ingresa tu contraseña' : null,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading ? null : _loginWithPassword,
              child: _loading && _mode == LoginMode.password
                  ? _buildLoadingIndicator()
                  : const Text('Entrar'),
            ),
          ),
          if (_hasStoredCodigo)
            TextButton(
              onPressed: () => _onModeChanged(LoginMode.codigo),
              child: const Text('¿Prefieres usar tu código?'),
            ),
          if ((_storedUserName ?? '').isNotEmpty)
            TextButton(
              onPressed: _loading ? null : _useAnotherAccount,
              child: const Text('Usar otra cuenta'),
            ),
        ],
      ),
    );
  }

  Widget _buildCodigoForm(BuildContext context) {
    final codigoEnabled = (_storedUserName ?? '').isNotEmpty && _hasStoredCodigo;
    return Form(
      key: _pinFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              codigoEnabled
                  ? 'Usuario: $_storedUserName'
                  : 'No hay usuario almacenado. Inicia sesión con contraseña.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 12),
          // Campo de texto que muestra el código (solo lectura, sin teclado del sistema)
          TextFormField(
            controller: _codigoCtrl,
            obscureText: _obscureCodigo,
            readOnly: true,
            showCursor: false,
            maxLength: AppConfig.allowedCodigoLengths.last,
            decoration: InputDecoration(
              labelText: 'Código',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_codigoCtrl.text.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _codigoCtrl.clear();
                        });
                      },
                      icon: const Icon(Icons.backspace_outlined),
                      tooltip: 'Borrar',
                    ),
                  IconButton(
                    onPressed: () => setState(() => _obscureCodigo = !_obscureCodigo),
                    icon: Icon(_obscureCodigo ? Icons.visibility : Icons.visibility_off),
                    tooltip: _obscureCodigo ? 'Mostrar código' : 'Ocultar código',
                  ),
                ],
              ),
              counterText: '',
            ),
            validator: _validateCodigo,
          ),
          const SizedBox(height: 24),
          // Teclado numérico en pantalla
          _buildNumericKeyboard(context),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _loading || !codigoEnabled ? null : _loginWithCodigo,
              child: _loading && _mode == LoginMode.codigo
                  ? _buildLoadingIndicator()
                  : const Text('Entrar con código'),
            ),
          ),
          TextButton(
            onPressed: () => _onModeChanged(LoginMode.password),
            child: const Text('¿Prefieres usar tu contraseña?'),
          ),
          TextButton(
            onPressed: _loading ? null : _useAnotherAccount,
            child: const Text('Usar otra cuenta'),
          ),
        ],
      ),
    );
  }

  Widget _buildNumericKeyboard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    void _onNumberPressed(String number) {
      if (_codigoCtrl.text.length < AppConfig.allowedCodigoLengths.last) {
        setState(() {
          _codigoCtrl.text += number;
        });
      }
    }

    void _onBackspacePressed() {
      if (_codigoCtrl.text.isNotEmpty) {
        setState(() {
          _codigoCtrl.text = _codigoCtrl.text.substring(0, _codigoCtrl.text.length - 1);
        });
      }
    }

    Widget _buildKey(String label, VoidCallback onPressed, {bool isBackspace = false}) {
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

    return Column(
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
    );
  }

  Widget _buildLoadingIndicator() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 8),
        Text(
          _loadingMessage,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

