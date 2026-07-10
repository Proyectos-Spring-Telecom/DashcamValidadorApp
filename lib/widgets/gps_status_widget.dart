import 'dart:async';

import 'package:flutter/material.dart';
import '../services/global_gps_service.dart';

/// Widget que muestra el estado actual del GPS de forma compacta
/// Puede ser usado en cualquier vista para monitorear el GPS
class GpsStatusWidget extends StatefulWidget {
  final bool showDetails;
  final bool autoStart;
  
  const GpsStatusWidget({
    super.key,
    this.showDetails = false,
    this.autoStart = false,
  });

  @override
  State<GpsStatusWidget> createState() => _GpsStatusWidgetState();
}

class _GpsStatusWidgetState extends State<GpsStatusWidget> {
  static const String _listenerId = 'gps_status_widget';

  @override
  void initState() {
    super.initState();
    
    // Auto-iniciar GPS si se solicita
    if (widget.autoStart) {
      globalGpsService.registerListener(_listenerId);
      unawaited(globalGpsService.startPersistent());
    }
  }

  @override
  void dispose() {
    if (widget.autoStart) {
      globalGpsService.unregisterListener(_listenerId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Usar ListenableBuilder para escuchar cambios automáticamente
    return ListenableBuilder(
      listenable: globalGpsService,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final location = globalGpsService.currentLocation;
        final isActive = globalGpsService.isActive;
        final isLoading = globalGpsService.isLoadingLocation;
        final updateCount = globalGpsService.updateCount;
        final healthStatus = globalGpsService.healthStatus;
        final errorMessage = globalGpsService.errorMessage;
        
        // Determinar color y icono basado en el estado de salud
        Color statusColor;
        IconData statusIcon;
        String statusText;
        
        switch (healthStatus) {
          case GpsHealthStatus.healthy:
            statusColor = cs.tertiary;
            statusIcon = Icons.gps_fixed;
            statusText = 'GPS Saludable';
            break;
          case GpsHealthStatus.degraded:
            statusColor = cs.secondary;
            statusIcon = Icons.gps_not_fixed;
            statusText = 'GPS Degradado';
            break;
          case GpsHealthStatus.unhealthy:
            statusColor = cs.error;
            statusIcon = Icons.gps_off;
            statusText = 'GPS No Saludable';
            break;
          case GpsHealthStatus.disconnected:
            statusColor = cs.onSurfaceVariant;
            statusIcon = Icons.gps_off;
            statusText = 'GPS Desconectado';
            break;
          case GpsHealthStatus.unknown:
          default:
            statusColor = cs.onSurfaceVariant;
            statusIcon = Icons.gps_not_fixed;
            statusText = 'GPS Inicializando';
            break;
        }

        if (widget.showDetails) {
          // Vista detallada
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isLoading ? Icons.gps_not_fixed : statusIcon,
                        color: isLoading ? cs.primary : statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estado del GPS',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (errorMessage != null)
                              Text(
                                errorMessage!,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (isLoading)
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusText,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (location != null && isActive) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• ${location.clasificacionExactitud} (±${location.exactitud.toStringAsFixed(1)}m)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  if (updateCount > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Actualizaciones: $updateCount',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        } else {
          // Vista compacta
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLoading ? Icons.gps_not_fixed : statusIcon,
                  size: 14,
                  color: isLoading ? cs.primary : statusColor,
                ),
                const SizedBox(width: 4),
                Text(
                  isLoading 
                      ? 'GPS...'
                      : healthStatus == GpsHealthStatus.healthy
                          ? 'GPS OK'
                          : healthStatus == GpsHealthStatus.degraded
                              ? 'GPS Lento'
                              : healthStatus == GpsHealthStatus.unhealthy
                                  ? 'GPS Error'
                                  : 'Sin GPS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isLoading ? cs.primary : statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (updateCount > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '($updateCount)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: statusColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          );
        }
      },
    );
  }
}
