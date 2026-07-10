import 'package:flutter/material.dart';

/// Widget reutilizable para mostrar estados de carga
/// Proporciona una interfaz consistente para loading en toda la app
class LoadingWidget extends StatelessWidget {
  final String? message;
  final bool isFullScreen;
  final Color? backgroundColor;

  const LoadingWidget({
    super.key,
    this.message,
    this.isFullScreen = false,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loadingContent = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator.adaptive(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(
            message!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );

    if (isFullScreen) {
      return Scaffold(
        backgroundColor: backgroundColor ?? cs.surface,
        body: Center(child: loadingContent),
      );
    }

    return Center(child: loadingContent);
  }
}

/// Widget para mostrar un botón con estado de carga
class LoadingButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;
  final String? loadingMessage;
  final Widget? icon;

  const LoadingButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.isLoading = false,
    this.loadingMessage,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isLoading ? null : onPressed,
      icon: isLoading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            )
          : (icon ?? const SizedBox.shrink()),
      label: Text(isLoading ? (loadingMessage ?? label) : label),
    );
  }
}

