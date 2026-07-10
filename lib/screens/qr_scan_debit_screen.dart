import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/device_capabilities.dart';

/// Pantalla de cámara para leer un QR y devolver el texto crudo (trim).
/// En web no está soportado: hace pop con null.
class QrScanDebitScreen extends StatefulWidget {
  const QrScanDebitScreen({super.key});

  @override
  State<QrScanDebitScreen> createState() => _QrScanDebitScreenState();
}

class _QrScanDebitScreenState extends State<QrScanDebitScreen> {
  bool _handled = false;
  MobileScannerController? _controller;
  bool _noCamera = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _initScanner();
  }

  Future<void> _initScanner() async {
    if (kIsWeb) return;
    final hasCamera = await DeviceCapabilities.hasCamera();
    if (!mounted) return;
    if (!hasCamera) {
      setState(() {
        _noCamera = true;
        _ready = true;
      });
      return;
    }
    setState(() {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        facing: CameraFacing.front,
      );
      _ready = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue ?? barcode.displayValue;
      if (value != null && value.trim().isNotEmpty) {
        _handled = true;
        final v = value.trim();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop<String>(v);
        });
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop<String>(null);
      });
      return const Scaffold(
        body: Center(child: Text('El escaneo QR no está disponible en web.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear código QR'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop<String>(null),
        ),
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _noCamera || _controller == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Este dispositivo no tiene cámara para escanear QR.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                )
              : Stack(
                  children: [
                    MobileScanner(
                      controller: _controller!,
                      onDetect: _onDetect,
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Apunta al código QR del pasajero',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
