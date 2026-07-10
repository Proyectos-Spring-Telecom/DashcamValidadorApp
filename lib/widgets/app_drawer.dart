import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../app/auth.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: cs.primary.withOpacity(.08),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: cs.primary,
                    backgroundImage: auth.fotoPerfil != null && auth.fotoPerfil!.isNotEmpty
                        ? NetworkImage(auth.fotoPerfil!)
                        : null,
                    child: auth.fotoPerfil == null || auth.fotoPerfil!.isEmpty
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
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
            ListTile(
              leading: const Icon(Icons.home_outlined),
              title: const Text('Inicio'),
              onTap: () => context.go('/home'),
            ),
            ListTile(
              leading: const Icon(Icons.history_outlined),
              title: const Text('Actividad'),
              onTap: () => context.go('/activity'),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('Recargar Monedero'),
              onTap: () {
                Navigator.of(context).pop();
                context.push('/recharge');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Configuración'),
              onTap: () => context.go('/settings'),
            ),
            const Spacer(),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Salir'),
              onTap: () {
                auth.logout();
                context.go('/login');
              },
            ),
          ],
        ),
      ),
    );
  }
}

