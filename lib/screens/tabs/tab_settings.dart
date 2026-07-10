import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../app/auth.dart';

class TabSettings extends StatefulWidget {
  const TabSettings({super.key});

  @override
  State<TabSettings> createState() => _TabSettingsState();
}

class _TabSettingsState extends State<TabSettings> {
  String _appVersion = 'Cargando...';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Desconocida';
      });
    }
  }

  void _showAboutBottomSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de arrastre
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            
            // Logo de la aplicación
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.directions_bus,
                size: 40,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 20),
            
            // Nombre de la aplicación
            Text(
              'DashCam',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            
            // Versión
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Versión $_appVersion',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.onSecondaryContainer,
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // Separador
            Divider(color: cs.outlineVariant),
            const SizedBox(height: 16),
            
            // Información de derechos
            Text(
              'Todos los derechos reservados a:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            Text(
              'GRUPO SIZEDEL S.A. de C.V.',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            
            Text(
              'Copyright ? ${DateTime.now().year}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            // Botón cerrar
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ),
            
            // Espacio adicional para dispositivos con notch
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Perfil del operador
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: cs.primary,
                  backgroundImage: auth.fotoPerfil != null && auth.fotoPerfil!.isNotEmpty
                      ? NetworkImage(auth.fotoPerfil!)
                      : null,
                  child: auth.fotoPerfil == null || auth.fotoPerfil!.isEmpty
                      ? const Icon(Icons.person, color: Colors.white, size: 32)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.nombreCompleto ?? 'Operador',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        auth.rol?.nombre ?? 'Operador',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      if (auth.nombreCliente != null)
                        Text(
                          auth.nombreCliente!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Configuración de seguridad
        _SettingsSection(
          title: 'Seguridad',
          items: [
            _SettingsItem(
              icon: Icons.lock,
              title: 'Configurar Código',
              subtitle: 'Establecer código de seguridad',
              onTap: () {
                context.push('/codigo-setup');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SettingsSection(
          title: 'Aplicación',
          items: [
            // _SettingsItem(
            //   icon: Icons.notifications,
            //   title: 'Notificaciones',
            //   subtitle: 'Configurar alertas',
            //   onTap: () {},
            // ),
            _SettingsItem(
              icon: Icons.info,
              title: 'Acerca de',
              subtitle: 'Versión y información',
              onTap: () => _showAboutBottomSheet(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> items;

  const _SettingsSection({
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Card(
          child: Column(
            children: items,
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

