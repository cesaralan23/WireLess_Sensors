import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'ble_gateway_service.dart';
import 'models.dart';

class AddGatewayWizard extends StatefulWidget {
  final DashboardController controller;
  const AddGatewayWizard({super.key, required this.controller});

  @override
  State<AddGatewayWizard> createState() => _AddGatewayWizardState();
}

class _AddGatewayWizardState extends State<AddGatewayWizard> {
  final BleGatewayService _ble = BleGatewayService();

  StreamSubscription<List<ScanResult>>? _scanSub;
  List<ScanResult> _results = [];
  BluetoothDevice? _selected;
  bool _connecting = false;
  String? _deviceId;
  bool _applyLoading = false;
  String? _applyStatus;

  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _startScan() async {
    _results = [];
    setState(() {});
    await FlutterBluePlus.stopScan();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      // Opcional: filtrar por nombre/servicio si tu gateway anuncia algo específico
      setState(() {
        _results = list;
      });
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
  }

  Future<void> _connect(ScanResult r) async {
    setState(() {
      _connecting = true;
      _selected = r.device;
      _applyStatus = null;
    });
    try {
      await _ble.connectTo(
        r.device,
        onStatus: (s) {
          setState(() {
            _applyStatus = s;
          });
        },
        onDeviceId: (id) {
          setState(() {
            _deviceId = id;
          });
        },
        onWifiPacket: (pkt) {
          // Podemos usar paquetes WiFi para mostrar avance si escaneamos redes
        },
      );
      setState(() {
        _connecting = false;
      });
    } catch (e) {
      setState(() {
        _connecting = false;
        _applyStatus = 'Error conectando: $e';
      });
    }
  }

  Future<void> _applyWifi() async {
    if (_selected == null) return;
    setState(() {
      _applyLoading = true;
      _applyStatus = null;
    });
    try {
      await _ble.apply(_ssidCtrl.text.trim(), _passCtrl.text.trim());
      setState(() {
        _applyLoading = false;
        _applyStatus = 'Credenciales aplicadas. El gateway intentará conectarse a WiFi.';
      });
    } catch (e) {
      setState(() {
        _applyLoading = false;
        _applyStatus = 'Falló aplicar WiFi: $e';
      });
    }
  }

  Future<void> _finishAndAdd() async {
    if (_deviceId == null) {
      setState(() {
        _applyStatus = 'Conecta a un gateway primero.';
      });
      return;
    }
    final nameCtrl = TextEditingController();
    final locCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Agregar gateway'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ID: ${_deviceId}'),
              const SizedBox(height: 12),
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')), 
              TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Ubicación')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        );
      },
    );
    if (ok == true) {
      widget.controller.addGateway(nameCtrl.text.trim(), locCtrl.text.trim(), id: _deviceId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular gateway')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1) Escanea y selecciona tu gateway'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  return ListTile(
                    title: Text(r.device.platformName.isNotEmpty ? r.device.platformName : 'Dispositivo BLE'),
                    subtitle: Text(r.device.remoteId.str),
                    trailing: _connecting && _selected == r.device
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : TextButton(onPressed: () => _connect(r), child: const Text('Conectar')),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              children: [
                const Text('ID del gateway: '),
                Text(_deviceId ?? '—'),
                const Spacer(),
                IconButton(onPressed: _startScan, icon: const Icon(Icons.refresh)),
              ],
            ),
            const SizedBox(height: 12),
            const Text('2) Ingresa SSID y clave WiFi'),
            const SizedBox(height: 8),
            TextField(controller: _ssidCtrl, decoration: const InputDecoration(labelText: 'SSID')), 
            TextField(controller: _passCtrl, decoration: const InputDecoration(labelText: 'Clave')), 
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _applyLoading ? null : _applyWifi, child: const Text('Aplicar WiFi')),
                const SizedBox(width: 12),
                if (_applyLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_applyStatus != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_applyStatus!),
            ),
            const SizedBox(height: 16),
            const Text('3) Agregar a la lista de gateways'),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton(onPressed: _finishAndAdd, child: const Text('Agregar gateway')),
                const SizedBox(width: 12),
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cerrar')),
              ],
            )
          ],
        ),
      ),
    );
  }
}