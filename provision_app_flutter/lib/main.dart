import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dart:async';

// UUIDs del servicio/ características (deben coincidir con el ESP32)
final Guid provService = Guid("fefefefe-1234-5678-9abc-def012345678");
final Guid ssidChar = Guid("fefefefe-1234-5678-9abc-def012345679");
final Guid passChar = Guid("fefefefe-1234-5678-9abc-def01234567a");
final Guid applyChar = Guid("fefefefe-1234-5678-9abc-def01234567b");
final Guid statusChar = Guid("fefefefe-1234-5678-9abc-def01234567c");
final Guid deviceIdChar = Guid("fefefefe-1234-5678-9abc-def01234567d");
final Guid wifiScanReqChar = Guid("fefefefe-1234-5678-9abc-def01234567e");
final Guid wifiScanResChar = Guid("fefefefe-1234-5678-9abc-def01234567f");

class WifiNet {
  final String ssid;
  final int rssi;
  final bool secure;
  WifiNet(this.ssid, this.rssi, this.secure);
}

class MockGateway {
  final String name;
  final int rssi;
  final String mac;
  MockGateway(this.name, this.rssi, this.mac);
}

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 WiFi Provision',
      theme: ThemeData(primarySwatch: Colors.green),
      home: const ProvisionPage(),
    );
  }
}

class ProvisionPage extends StatefulWidget {
  const ProvisionPage({super.key});
  @override
  State<ProvisionPage> createState() => _ProvisionPageState();
}

class _ProvisionPageState extends State<ProvisionPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? ssidC;
  BluetoothCharacteristic? passC;
  BluetoothCharacteristic? applyC;
  BluetoothCharacteristic? statusC;
  BluetoothCharacteristic? deviceIdC;
  BluetoothCharacteristic? wifiScanReqC;
  BluetoothCharacteristic? wifiScanResC;

  final ssidCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final passFocus = FocusNode();
  String statusText = 'idle';
  List<ScanResult> gateways = [];
  bool isScanning = false;
  String connectedName = '';
  String gatewayIdText = '';
  bool filterPrefix = true;
  bool showPass = false;
  bool applyBusy = false;

  List<WifiNet> wifiNets = [];
  bool wifiScanning = false;
  StreamSubscription<List<int>>? wifiScanSub;
  List<MockGateway> mockGateways = [];

  Color _statusColor() {
    switch (statusText) {
      case 'awaiting':
        return Colors.amber.shade200;
      case 'connecting':
        return Colors.blue.shade200;
      case 'success':
        return Colors.green.shade300;
      case 'fail':
        return Colors.red.shade300;
      case 'permission_denied':
        return Colors.grey.shade300;
      case 'connect_error':
        return Colors.orange.shade300;
      default:
        return Colors.grey.shade200;
    }
  }

  IconData _wifiBars(int rssi) {
    // Usamos el icono de 4 barras y variamos la opacidad según RSSI
    return Icons.signal_wifi_4_bar;
  }

  double _wifiOpacity(int rssi) {
    final bars = rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -80 ? 2 : 1;
    switch (bars) {
      case 4:
        return 1.0;
      case 3:
        return 0.8;
      case 2:
        return 0.6;
      default:
        return 0.4;
    }
  }

  Future<bool> _ensureBlePermissions() async {
    if (!Platform.isAndroid) return true;
    final perms = [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];
    final statuses = await perms.request();
    final granted = statuses.values.every((s) => s.isGranted);
    return granted;
  }

  Future<void> scanAndConnect() async {
    final ok = await _ensureBlePermissions();
    if (!ok) {
      setState(() => statusText = 'permission_denied');
      return;
    }

    gateways = [];
    setState(() => isScanning = true);

    final sub = FlutterBluePlus.scanResults.listen((rs) {
      // Filtra por servicio y, opcionalmente, por prefijo del nombre
      final filtered = rs.where((r) {
        final byService = r.advertisementData.serviceUuids.contains(provService);
        final name = (r.device.platformName.isNotEmpty == true)
            ? r.device.platformName
            : (r.device.advName ?? '');
        final byPrefix = filterPrefix ? name.startsWith('ESP32-Gateway') : true;
        return byService && byPrefix;
      }).toList();
      setState(() => gateways = filtered);
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8), withServices: [provService]);
    await FlutterBluePlus.isScanning.where((s) => s == false).first;
    await FlutterBluePlus.stopScan();
    await sub.cancel();

    setState(() => isScanning = false);
  }

  Future<void> connectTo(BluetoothDevice d) async {
    try {
      device = d;
      await device!.connect(timeout: const Duration(seconds: 10));
      final services = await device!.discoverServices();
      for (final s in services) {
        if (s.uuid == provService) {
          for (final c in s.characteristics) {
            if (c.uuid == ssidChar) ssidC = c;
            if (c.uuid == passChar) passC = c;
            if (c.uuid == applyChar) applyC = c;
            if (c.uuid == statusChar) statusC = c;
            if (c.uuid == deviceIdChar) deviceIdC = c;
            if (c.uuid == wifiScanReqChar) wifiScanReqC = c;
            if (c.uuid == wifiScanResChar) wifiScanResC = c;
          }
        }
      }
      if (statusC != null) {
        await statusC!.setNotifyValue(true);
        statusC!.onValueReceived.listen((data) {
          setState(() => statusText = String.fromCharCodes(data));
        });
      }

      if (wifiScanResC != null) {
        await wifiScanResC!.setNotifyValue(true);
        await wifiScanSub?.cancel();
        wifiScanSub = wifiScanResC!.onValueReceived.listen((data) {
          final txt = String.fromCharCodes(data);
          if (txt == 'END') {
            setState(() => wifiScanning = false);
            return;
          }
          final parts = txt.split('|');
          if (parts.length >= 3) {
            final ssid = parts[0];
            final rssi = int.tryParse(parts[1]) ?? -100;
            final secure = parts[2] != '0';
            setState(() {
              wifiNets.add(WifiNet(ssid, rssi, secure));
              wifiNets.sort((a, b) => b.rssi.compareTo(a.rssi));
            });
          }
        });
      }

      connectedName = device!.platformName.isNotEmpty == true
          ? device!.platformName
          : (device!.advName ?? device!.remoteId.str);

      // Lee el DEVICE_ID para confirmar a qué gateway hablamos
      if (deviceIdC != null) {
        final idBytes = await deviceIdC!.read();
        gatewayIdText = String.fromCharCodes(idBytes);
      }
      setState(() {});
    } catch (e) {
      setState(() => statusText = 'connect_error');
    }
  }

  Future<void> disconnect() async {
    try {
      await device?.disconnect();
    } catch (_) {}
    await wifiScanSub?.cancel();
    setState(() {
      device = null;
      ssidC = null;
      passC = null;
      applyC = null;
      statusC = null;
      deviceIdC = null;
      wifiScanReqC = null;
      wifiScanResC = null;
      connectedName = '';
      gatewayIdText = '';
      wifiNets.clear();
      wifiScanning = false;
    });
  }

  Future<void> scanWifi() async {
    if (wifiScanReqC == null) return;
    setState(() {
      wifiNets.clear();
      wifiScanning = true;
    });
    await wifiScanReqC!.write([1], withoutResponse: false);
  }

  void addDemoData() {
    setState(() {
      // Limpiar anteriores para evitar duplicados
      wifiNets.clear();
      mockGateways.clear();

      // Redes WiFi demo variadas
      wifiNets.addAll([
        WifiNet('WiFi Fantasma', -66, true),       // ~75% (segura)
        WifiNet('Café Libre', -50, false),         // fuerte y abierta
        WifiNet('Casa-2G', -80, true),             // débil y segura
        WifiNet('', -73, true),                    // SSID oculto
        WifiNet('Oficina', -60, true),             // media/alta y segura
      ]);
      wifiNets.sort((a, b) => b.rssi.compareTo(a.rssi));

      // Gateways demo
      mockGateways = [
        MockGateway('ESP32-Gateway DEMO (ID 80A5CC)', -66, 'AA:BB:CC:DD:EE:FF'),
        MockGateway('ESP32-Gateway DEMO-B (ID 123456)', -50, '11:22:33:44:55:66'),
        MockGateway('ESP32-Gateway DEMO-C (ID ABCDEF)', -82, '77:88:99:AA:BB:CC'),
      ];
    });
  }

  Future<void> apply() async {
    if (ssidC == null || passC == null || applyC == null) return;
    await ssidC!.write(ssidCtrl.text.codeUnits, withoutResponse: false);
    await passC!.write(passCtrl.text.codeUnits, withoutResponse: false);
    await applyC!.write([1], withoutResponse: false);
  }

  @override
  void dispose() {
    ssidCtrl.dispose();
    passCtrl.dispose();
    passFocus.dispose();
    wifiScanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisionar Gateway ESP32'),
        actions: [
          IconButton(
            tooltip: filterPrefix ? 'Filtrar por ESP32-Gateway-*' : 'Mostrar todos',
            icon: Icon(filterPrefix ? Icons.filter_alt : Icons.filter_alt_off),
            onPressed: () => setState(() => filterPrefix = !filterPrefix),
          ),
          IconButton(
            tooltip: 'Refrescar escaneo',
            icon: const Icon(Icons.refresh),
            onPressed: isScanning ? null : scanAndConnect,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: scanAndConnect,
              child: const Text('Buscar gateways (BLE)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: addDemoData,
              icon: const Icon(Icons.bug_report),
              label: const Text('Cargar demo UX'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => statusText = 'idle'),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Estado: idle'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => statusText = 'awaiting'),
                  icon: const Icon(Icons.hourglass_bottom),
                  label: const Text('Estado: awaiting'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => statusText = 'connecting'),
                  icon: const Icon(Icons.sync),
                  label: const Text('Estado: connecting'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => statusText = 'success'),
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Estado: success'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => statusText = 'fail'),
                  icon: const Icon(Icons.error_outline),
                  label: const Text('Estado: fail'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      wifiNets.clear();
                      mockGateways.clear();
                    });
                  },
                  icon: const Icon(Icons.cleaning_services),
                  label: const Text('Limpiar demo'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isScanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Gateways cercanos', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: gateways.length + mockGateways.length,
                itemBuilder: (context, i) {
                  if (i < gateways.length) {
                    final r = gateways[i];
                    final name = (r.device.platformName.isNotEmpty == true)
                        ? r.device.platformName
                        : (r.device.advName ?? r.device.remoteId.str);
                    return Card(
                      child: ListTile(
                        title: Text(name ?? 'ESP32-Gateway'),
                        subtitle: Text('RSSI: ${r.rssi} dBm · MAC: ${r.device.remoteId.str}'),
                        trailing: TextButton.icon(
                          onPressed: () => connectTo(r.device),
                          icon: const Icon(Icons.link),
                          label: const Text('Conectar'),
                        ),
                        onTap: () => connectTo(r.device),
                      ),
                    );
                  } else {
                    final m = mockGateways[i - gateways.length];
                    return Card(
                      child: ListTile(
                        title: Text(m.name),
                        subtitle: Text('RSSI: ${m.rssi} dBm · MAC: ${m.mac}'),
                        trailing: TextButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Gateway DEMO — no conectable')),
                            );
                          },
                          icon: const Icon(Icons.link),
                          label: const Text('Conectar'),
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gateway DEMO — no conectable')),
                          );
                        },
                      ),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            if (device == null)
              const Text('Sin conexión')
            else
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Conectado a: ${connectedName.isNotEmpty ? connectedName : device!.remoteId.str}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text('ID: ${gatewayIdText.isNotEmpty ? gatewayIdText : '---'}'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: disconnect,
                            icon: const Icon(Icons.link_off),
                            label: const Text('Desconectar'),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: scanAndConnect,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Re-escanear'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Sección de redes WiFi escaneadas por el gateway (BLE)
            if (device != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Redes WiFi cercanas', style: TextStyle(fontWeight: FontWeight.w600)),
                  TextButton.icon(
                    onPressed: (wifiScanReqC != null && !wifiScanning) ? scanWifi : null,
                    icon: const Icon(Icons.wifi_find),
                    label: Text(wifiScanning ? 'Buscando...' : 'Buscar WiFi'),
                  ),
                ],
              ),
              if (wifiScanning) const LinearProgressIndicator(minHeight: 2),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: wifiNets.length,
                  itemBuilder: (context, i) {
                    final n = wifiNets[i];
                    return Card(
                      child: ListTile(
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_wifiBars(n.rssi), color: Colors.blueGrey.withOpacity(_wifiOpacity(n.rssi))),
                            const SizedBox(width: 6),
                            Icon(n.secure ? Icons.lock : Icons.lock_open, size: 16, color: Colors.grey[700]),
                          ],
                        ),
                        title: Text(n.ssid.isNotEmpty ? n.ssid : '<SSID oculto>'),
                        subtitle: Text('RSSI: ${n.rssi} dBm'),
                        trailing: TextButton(
                          onPressed: () {
                            setState(() {
                              ssidCtrl.text = n.ssid;
                            });
                            if (n.secure) {
                              FocusScope.of(context).requestFocus(passFocus);
                            }
                          },
                          child: const Text('Elegir'),
                        ),
                        onTap: () {
                          setState(() {
                            ssidCtrl.text = n.ssid;
                          });
                          if (n.secure) {
                            FocusScope.of(context).requestFocus(passFocus);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: ssidCtrl,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            TextField(
              controller: passCtrl,
              focusNode: passFocus,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => showPass = !showPass),
                ),
              ),
              obscureText: !showPass,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (device != null && ssidCtrl.text.isNotEmpty && !applyBusy)
                  ? () async {
                      setState(() => applyBusy = true);
                      await apply();
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Credenciales enviadas. Verificando estado...')),
                        );
                      }
                      setState(() => applyBusy = false);
                    }
                  : null,
              child: applyBusy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Aplicar credenciales'),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _statusColor(),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Estado: $statusText'),
            ),
          ],
        ),
      ),
    );
  }
}