import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'app/auth.dart';
import 'services/http_service.dart';
import 'utils/logger.dart';

/// Punto de entrada de la aplicación
/// Inicializa servicios globales antes de ejecutar la app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configurar manejo global de errores no capturados
  ErrorWidget.builder = (FlutterErrorDetails details) {
    appLogger.e(
      'Error no capturado en la UI',
      details.exception,
      details.stack,
    );
    return Material(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Ha ocurrido un error',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (kDebugMode)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  details.exception.toString(),
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  };

  // Inicializar servicios con manejo de errores
  try {
    appLogger.i('Inicializando servicios de la aplicación');
    await httpService.initialize();
    await auth.initialize();
    appLogger.i('Servicios inicializados correctamente');
  } catch (e, stackTrace) {
    appLogger.f('Error crítico al inicializar servicios', e, stackTrace);
    // En producción, podrías mostrar una pantalla de error o enviar el error a un servicio
    // Por ahora, continuamos para que la app intente iniciar
  }

  // Solicitar permisos de ubicación al iniciar (independiente de si el GPS está encendido)
  try {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        appLogger.i('Permisos de ubicación concedidos');
      } else {
        appLogger.w('Permisos de ubicación denegados: $permission');
      }
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      appLogger.w(
        'El servicio de ubicación del dispositivo está apagado; '
        'actívalo en Ajustes para que el GPS funcione.',
      );
    }
  } catch (e) {
    appLogger.w('No se pudieron solicitar permisos de ubicación: $e');
  }

  runApp(const DashCamApp());
}

class DashCamApp extends StatelessWidget {
  const DashCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = buildDashCamTheme();
    final router = buildRouter(auth);

    return ListenableBuilder(
      listenable: auth, // Reconstruye cuando cambia el estado de autenticación
      builder: (context, _) {
        return MaterialApp.router(
          title: 'DashCam',
          debugShowCheckedModeBanner: false,
          theme: theme.light,
          darkTheme: theme.dark,
          themeMode: ThemeMode.system,
          routerConfig: router,
          locale: const Locale('es', 'MX'),
          supportedLocales: const [Locale('es', 'MX'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return child ?? const SizedBox.shrink();
          },
        );
      },
    );
  }
}
