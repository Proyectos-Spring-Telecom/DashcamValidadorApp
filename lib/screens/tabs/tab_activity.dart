import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/activity_response.dart';
import '../../services/global_gps_service.dart';
import '../../services/native_gps_service.dart';
import '../../services/activity_service.dart';

class TabActivity extends StatefulWidget {
  const TabActivity({super.key});

  @override
  State<TabActivity> createState() => _TabActivityState();
}

class _TabActivityState extends State<TabActivity> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  static const String _listenerId = 'tab_activity';
  bool _mapReady = false; // Flag para verificar que el mapa esté listo

  ActivityResponse? _activity;
  bool _loadingActivity = false;
  String? _activityError;
  LatLng? _apiLatLng; // ultimaPosicion del API (si existe)

  // Ubicación por defecto (Ciudad de México) mientras se obtiene el GPS
  static const LatLng _defaultLocation = LatLng(19.432608, -99.133209);
  LatLng _currentLatLng = _defaultLocation;
  LatLng _targetLatLng = _defaultLocation;
  LatLng _interpolationStart = _defaultLocation;

  // Para animación suave del marcador y posición
  late AnimationController _markerAnimationController;
  late Animation<double> _markerAnimation;
  late AnimationController _positionAnimationController;
  late Animation<double> _positionAnimation;

  @override
  void initState() {
    super.initState();
    
    // Inicializar animación del marcador
    _markerAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _markerAnimation = CurvedAnimation(
      parent: _markerAnimationController,
      curve: Curves.easeOut,
    );
    
    // Inicializar animación de posición para interpolación suave
    _positionAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _positionAnimation = CurvedAnimation(
      parent: _positionAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Escuchar cambios en la animación de posición para actualizar el marcador
    _positionAnimation.addListener(_updateInterpolatedPosition);
    
    // Registrar listener en el servicio GPS global
    _registerGpsListener();

    // Cargar actividad (endpoint con numeroSerieValidador)
    _loadActivity();
  }

  /// Llama al endpoint de actividad concatenando numeroSerieValidador
  Future<void> _loadActivity() async {
    if (!mounted) return;
    setState(() {
      _loadingActivity = true;
      _activityError = null;
      _activity = null;
    });
    final result = await activityService.getActivity();
    if (!mounted) return;
    final ultima = result?.data.ultimaPosicion;
    final latLngFromApi = ultima != null ? LatLng(ultima.latitud, ultima.longitud) : null;
    setState(() {
      _loadingActivity = false;
      _activity = result;
      _activityError = result == null ? 'No se pudo cargar la actividad' : null;
      // Usar lat/lon de ultimaPosicion del API para el mapa cuando exista
      if (latLngFromApi != null) {
        _apiLatLng = latLngFromApi;
        _currentLatLng = latLngFromApi;
        _targetLatLng = latLngFromApi;
        _interpolationStart = latLngFromApi;
      }
    });
    _centerMapOnApiIfAvailable();
  }

  void _centerMapOnApiIfAvailable() {
    final pos = _apiLatLng;
    if (pos == null || !_mapReady) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(pos, _mapController.camera.zoom);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    // Desregistrar listener del servicio GPS global
    globalGpsService.unregisterListener(_listenerId);
    
    _markerAnimationController.dispose();
    _positionAnimationController.dispose();
    super.dispose();
  }

  /// Registra este widget como listener del GPS global
  Future<void> _registerGpsListener() async {
    await globalGpsService.registerListener(_listenerId);
  }

  /// Callback cuando el servicio GPS global se actualiza
  /// Se llama manualmente desde el build usando ListenableBuilder
  void _onGpsServiceUpdate() {
    if (!mounted) return;
    
    final location = globalGpsService.currentLocation;
    if (location != null) {
      _handleLocationUpdate(location);
    }
  }

  void _updateInterpolatedPosition() {
    if (!mounted) return;
    
    const distance = Distance();
    final totalDistance = distance(_interpolationStart, _targetLatLng);
    
    if (totalDistance < 0.1) {
      // Distancia muy pequeña, usar posición objetivo directamente
      setState(() {
        _currentLatLng = _targetLatLng;
      });
      return;
    }

    // Usar interpolación suave con curva easeInOut para movimiento más natural
    final progress = _positionAnimation.value;
    
    // Interpolación lineal de coordenadas para movimiento más suave
    final latDiff = _targetLatLng.latitude - _interpolationStart.latitude;
    final lonDiff = _targetLatLng.longitude - _interpolationStart.longitude;
    
    final newLat = _interpolationStart.latitude + (latDiff * progress);
    final newLon = _interpolationStart.longitude + (lonDiff * progress);
    
    setState(() {
      _currentLatLng = LatLng(newLat, newLon);
    });
  }

  void _handleLocationUpdate(NativeGpsLocationResponse location) {
    if (!mounted) return;
    // Si tenemos ultimaPosicion del API, el mapa muestra esa posición y no la actualizamos con GPS en vivo
    if (_apiLatLng != null) return;

    // Verificar si tenemos coordenadas válidas
    if (location.isValid && location.exactitud < 500) {
      final newLatLng = LatLng(location.lat, location.lon);
      const distance = Distance();
      final distanceToNew = distance(_currentLatLng, newLatLng);
      final shouldMoveCamera = _mapReady && (globalGpsService.updateCount <= 1 || distanceToNew > 10);

      if (shouldMoveCamera) {
        try {
          _mapController.move(newLatLng, _mapController.camera.zoom);
        } catch (_) {}
      }

      _interpolationStart = _currentLatLng;
      _targetLatLng = newLatLng;
      _currentLatLng = newLatLng;
      _markerAnimationController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Usar ListenableBuilder para escuchar cambios en el GPS
    return ListenableBuilder(
      listenable: globalGpsService,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        // Actualizar cuando cambie el GPS - usar postFrameCallback para evitar setState durante build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _onGpsServiceUpdate();
          }
        });
        return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Mapa con ubicación GPS
        Card(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 300,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _apiLatLng ?? _currentLatLng,
                    initialZoom: 16.0,
                    minZoom: 5.0,
                    maxZoom: 18.0,
                    onMapReady: () {
                      if (mounted) {
                        setState(() => _mapReady = true);
                        _centerMapOnApiIfAvailable();
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.dashcam',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _apiLatLng ?? _currentLatLng,
                          width: 40,
                          height: 40,
                          child: AnimatedBuilder(
                            animation: _markerAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: 1.0 + (_markerAnimation.value * 0.1),
                                child: Transform.rotate(
                                  angle: globalGpsService.currentLocation?.tieneDireccion == true && globalGpsService.currentLocation!.isMoving
                                      ? (globalGpsService.currentLocation!.direccion * 3.14159 / 180)
                                      : 0,
                                  child: Icon(
                                    globalGpsService.currentLocation?.isMoving == true 
                                        ? Icons.navigation 
                                        : Icons.location_on,
                                    color: cs.primary,
                                    size: 40,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Indicador de estado GPS simple
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (globalGpsService.isLoadingLocation)
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                            ),
                          )
                        else
                          Icon(
                            globalGpsService.currentLocation?.isValid == true
                                ? Icons.gps_fixed
                                : Icons.gps_off,
                            size: 16,
                            color: globalGpsService.currentLocation?.isValid == true
                                ? cs.tertiary
                                : cs.error,
                          ),
                        const SizedBox(width: 8),
                        Text(
                          globalGpsService.isLoadingLocation
                              ? 'Obteniendo...'
                              : globalGpsService.currentLocation?.isValid == true
                                  ? 'GPS Activo'
                                  : 'Sin GPS',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Franja de estado del GPS (siempre visible)
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: globalGpsService.currentLocation?.esConfiable == true 
                ? cs.primaryContainer 
                : globalGpsService.currentLocation?.isValid == true
                    ? cs.secondaryContainer
                    : cs.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(
                    globalGpsService.currentLocation?.esConfiable == true 
                        ? Icons.gps_fixed 
                        : globalGpsService.currentLocation?.isValid == true
                            ? Icons.gps_not_fixed
                            : Icons.gps_off, 
                    color: globalGpsService.currentLocation?.esConfiable == true 
                        ? cs.onPrimaryContainer 
                        : globalGpsService.currentLocation?.isValid == true
                            ? cs.onSecondaryContainer
                            : cs.onErrorContainer, 
                    size: 20
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          globalGpsService.currentLocation?.esConfiable == true 
                              ? 'GPS Activo (Modo Rápido)' 
                              : globalGpsService.currentLocation?.isValid == true
                                  ? 'GPS con baja precisión'
                                  : globalGpsService.errorMessage ?? 'GPS no disponible',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: globalGpsService.currentLocation?.esConfiable == true 
                                ? cs.onPrimaryContainer 
                                : globalGpsService.currentLocation?.isValid == true
                                    ? cs.onSecondaryContainer
                                    : cs.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (globalGpsService.updateCount > 0)
                          Text(
                            'Actualizaciones: ${globalGpsService.updateCount}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (_activity?.data.ultimaPosicion != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Última posición',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'LAT: ${_activity!.data.ultimaPosicion!.latitud.toStringAsFixed(6)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                ),
                          ),
                          Text(
                            'LON: ${_activity!.data.ultimaPosicion!.longitud.toStringAsFixed(6)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ] else if (globalGpsService.currentLocation != null) ...[
                const SizedBox(height: 8),
                // Primera fila: Velocidad y Proveedor
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${globalGpsService.currentLocation!.velocidadKmh.toStringAsFixed(1)} km/h',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            globalGpsService.currentLocation!.isMoving
                                ? 'En movimiento • ${globalGpsService.currentLocation!.direccionCardinal}'
                                : 'Detenido',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${globalGpsService.currentLocation!.clasificacionExactitud.replaceAll('_', ' ')} (±${globalGpsService.currentLocation!.exactitud.toStringAsFixed(1)}m)',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Segunda fila: Coordenadas
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LAT: ${globalGpsService.currentLocation!.lat.toStringAsFixed(6)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'LON: ${globalGpsService.currentLocation!.lon.toStringAsFixed(6)}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: globalGpsService.currentLocation?.esConfiable == true 
                                  ? cs.onPrimaryContainer 
                                  : globalGpsService.currentLocation?.isValid == true
                                      ? cs.onSecondaryContainer
                                      : cs.onErrorContainer,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Lista de actividad
        Text(
          'Actividad reciente',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (_loadingActivity)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24.0),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_activityError != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Icon(Icons.error_outline, size: 48, color: cs.error),
                  const SizedBox(height: 12),
                  Text(
                    _activityError!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (_activity != null && _activity!.data.viajes.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(
                    Icons.history,
                    size: 64,
                    color: cs.onSurfaceVariant.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay actividad registrada',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else if (_activity != null && _activity!.data.viajes.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _activity!.data.viajes.map((v) {
              final fecha = v.fechaInicio != null
                  ? '${v.fechaInicio!.day}/${v.fechaInicio!.month}/${v.fechaInicio!.year} ${v.fechaInicio!.hour}:${v.fechaInicio!.minute.toString().padLeft(2, '0')}'
                  : '—';
              String? instalacionLine;
              final veh = v.instalacion?.vehiculo;
              if (veh != null) {
                final parts = <String>[];
                if (veh.placa != null && veh.placa!.isNotEmpty) parts.add(veh.placa!);
                final marcaModelo = [veh.marca, veh.modelo].whereType<String>().where((s) => s.isNotEmpty).join(' ').trim();
                if (marcaModelo.isNotEmpty) parts.add(marcaModelo);
                instalacionLine = parts.isEmpty ? 'Instalación #${v.instalacion!.idInstalacion}' : parts.join(' · ');
              } else if (v.instalacion != null) {
                instalacionLine = 'Instalación #${v.instalacion!.idInstalacion}';
              }
              return _ActivityItem(
                icon: Icons.directions_car,
                title: 'Viaje #${v.idViaje}',
                subtitle: v.nombreVariante ?? 'Sin variante',
                time: fecha,
                color: cs.primary,
                instalacionInfo: instalacionLine,
              );
            }).toList(),
          )
        else
          const SizedBox.shrink(),
      ],
    );
      },
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String time;
  final Color color;
  final String? instalacionInfo;

  const _ActivityItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.color,
    this.instalacionInfo,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(subtitle),
            if (instalacionInfo != null && instalacionInfo!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                instalacionInfo!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              time,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

