import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/gps_status_widget.dart';

class HomeShell extends StatefulWidget {
  final StatefulNavigationShell navShell;
  const HomeShell({super.key, required this.navShell});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int get _currentIndex => widget.navShell.currentIndex;

  void _onNavChanged(int idx) {
    widget.navShell.goBranch(idx, initialLocation: idx == _currentIndex);
  }

  String _titleForIndex(int i) {
    switch (i) {
      case 0:
        return 'Inicio';
      case 1:
        return 'Actividad';
      case 2:
        return 'Configuración';
      default:
        return 'DashCam';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titleForIndex(_currentIndex)),
        actions: [
          const GpsStatusWidget(showDetails: false),
          const SizedBox(width: 8),
          IconButton(onPressed: () {}, icon: const Icon(Icons.search)),
          const SizedBox(width: 4),
        ],
      ),
      drawer: const AppDrawer(),
      body: widget.navShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _onNavChanged,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.history_outlined), label: 'Actividad'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined), label: 'Ajustes'),
        ],
      ),
    );
  }
}

