import 'package:go_router/go_router.dart';
import '../screens/splash_screen.dart';
import '../screens/welcome_screen.dart';
import '../screens/login_screen.dart';
import '../screens/codigo_setup_screen.dart';
import '../screens/directo_screen.dart';
import '../screens/dynamic_fare_screen.dart';
import '../screens/meter_fare_screen.dart';
import '../screens/shell/home_shell.dart';
import '../screens/tabs/tab_home.dart';
import '../screens/tabs/tab_activity.dart';
import '../screens/tabs/tab_settings.dart';
import '../screens/recharge_screen.dart';
import 'auth.dart';

GoRouter buildRouter(AuthController auth) {
  bool isPublic(String? p) {
    // pantallas públicas (antes del login)
    return p == '/splash' || p == '/welcome' || p == '/login';
  }

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth, // Reevaluar redirects cuando cambie el estado
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (context, state) => const WelcomeScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/codigo-setup', builder: (context, state) => const CodigoSetupScreen()),
      GoRoute(path: '/directo', builder: (context, state) => const DirectoScreen()),
      GoRoute(path: '/dynamic-fare', builder: (context, state) => const DynamicFareScreen()),
      GoRoute(path: '/meter-fare', builder: (context, state) => const MeterFareScreen()),

      // Zona autenticada
      StatefulShellRoute.indexedStack(
        builder: (context, state, navShell) => HomeShell(navShell: navShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (context, state) => const TabHome()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/activity', builder: (context, state) => const TabActivity()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/settings', builder: (context, state) => const TabSettings()),
          ]),
        ],
      ),
      GoRoute(path: '/recharge', builder: (context, state) => const RechargeScreen()),
    ],
    redirect: (context, state) {
      final goingTo = state.fullPath;
      if (goingTo == '/' || goingTo == '') return '/splash';

      final loggedIn = auth.isLoggedIn;

      // Si ya está logueado y va a login, mándalo al home
      if (loggedIn && goingTo == '/login') return '/home';

      // Si no está logueado y va a una ruta privada, llévalo al login
      final isTryingPrivate = !isPublic(goingTo);
      if (!loggedIn && isTryingPrivate) return '/login';

      return null;
    },
  );
}

