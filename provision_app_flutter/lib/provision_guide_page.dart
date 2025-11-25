import 'package:flutter/material.dart';
import 'gateway_pages.dart';

class ProvisionGuidePage extends StatelessWidget {
  const ProvisionGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: const [
            Text('Cómo agregar un gateway', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('1) Ve a “Dashboard → Gateways”.'),
            Text('2) Toca “Agregar gateway”.'),
            Text('3) Selecciona el gateway BLE y conéctate.'),
            Text('4) Ingresa SSID y clave WiFi y presiona “Aplicar WiFi”.'),
            Text('5) Asigna nombre y ubicación y confirma.'),
            SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12.0),
        child: ElevatedButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const GatewaysPage()),
            );
          },
          icon: const Icon(Icons.router),
          label: const Text('Abrir Gateways'),
        ),
      ),
    );
  }
}