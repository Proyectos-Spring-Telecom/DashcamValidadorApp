import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/auth.dart';
import '../config/app_config.dart';
import '../utils/logger.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Inicializa la aplicación y navega según el estado
  Future<void> _initializeApp() async {
    final startTime = DateTime.now();

    try {
      appLogger.i('Inicializando aplicación...');
      
      // Aquí se pueden agregar tareas de inicialización
      // Por ejemplo: cargar configuraciones, verificar permisos, etc.
      await Future.delayed(const Duration(milliseconds: 500));

      // Asegurar duración mínima del splash
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed < AppConfig.minSplashDuration) {
        await Future.delayed(AppConfig.minSplashDuration - elapsed);
      }

      if (!mounted) return;

      // Navegar según el estado de autenticación
      final destination = auth.isLoggedIn ? '/home' : '/welcome';
      appLogger.i('Navegando a: $destination');
      context.go(destination);
    } catch (e) {
      appLogger.e('Error durante inicialización', e);
      if (mounted) {
        context.go('/welcome');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo de la aplicación
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
              'Plataforma de Gestión para el Transporte de Pasajeros.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator.adaptive(),
          ],
        ),
      ),
    );
  }
}

