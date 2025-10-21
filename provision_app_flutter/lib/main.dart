import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

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
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      const DashboardPage(),
      const ProvisionPage(),
    ];
    final titles = ['Dashboard', 'Configuración'];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Configuración'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Próximamente: dashboard de sensores'),
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
  final ssidFocus = FocusNode();
  String statusText = 'idle';
  List<ScanResult> gateways = [];
  bool isScanning = false;
  String connectedName = '';
  String gatewayIdText = '';
  bool filterPrefix = true;
  bool showPass = false;
  bool applyBusy = false;
  bool passEnabled = true;

  List<WifiNet> wifiNets = [];
  bool wifiScanning = false;
  StreamSubscription<List<int>>? wifiScanSub;
  Timer? wifiScanTimeout;
  List<MockGateway> mockGateways = [];
  int wifiPackets = 0;
  String lastWifiPacket = '';

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

  int _clampInt(int v, int min, int max) => v < min ? min : (v > max ? max : v);

  int _rssiToPercent(int rssi) {
    const int min = -90; // muy débil
    const int max = -55; // excelente
    final int clamped = _clampInt(rssi, min, max);
    final int pct = (((clamped - min) * 100) ~/ (max - min));
    return pct; // 0..100
  }

   IconData _wifiBars(int rssi) {
    final p = _rssiToPercent(rssi);
    return p <= 0 ? Icons.signal_wifi_0_bar : Icons.signal_wifi_4_bar;
   }
 
   double _wifiOpacity(int rssi) {
    final p = _rssiToPercent(rssi);
    if (p >= 75) return 1.0;
    if (p >= 50) return 0.85;
    if (p >= 25) return 0.65;
    if (p > 0) return 0.45;
    return 0.30;
  }

  Color _wifiColor(int rssi) {
    final p = _rssiToPercent(rssi);
    if (p >= 75) return Colors.black87;
    if (p >= 50) return Colors.grey.shade800;
    if (p >= 25) return Colors.grey.shade600;
    if (p > 0) return Colors.grey.shade500;
    return Colors.grey.shade400;
  }

  // Declaraciones de WifiStrengthIcon y _WifiPainter movidas a nivel superior.
 
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
      // Filtra por servicio o por nombre (más la opción de prefijo)
      final filtered = rs.where((r) {
        final byService = r.advertisementData.serviceUuids.contains(provService);
        final name = (r.device.platformName.isNotEmpty == true)
            ? r.device.platformName
            : (r.device.advName ?? '');
        final byPrefix = filterPrefix ? name.startsWith('ESP32-Gateway') : true;
        return byService || byPrefix;
      }).toList();
      setState(() => gateways = filtered);
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
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
          setState(() {
            wifiPackets++;
            lastWifiPacket = txt;
          });
          if (txt == 'END') {
            wifiScanTimeout?.cancel();
            setState(() => wifiScanning = false);
            if (wifiNets.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('No se encontraron redes Wi‑Fi')),
              );
            }
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
      wifiPackets = 0;
      lastWifiPacket = '';
    });
    // Programa timeout de seguridad por si el gateway no envía END
    wifiScanTimeout?.cancel();
    wifiScanTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (wifiScanning) {
        setState(() => wifiScanning = false);
        if (wifiNets.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sin resultados de Wi‑Fi (timeout)')),
          );
        }
      }
    });
    await wifiScanResC?.setNotifyValue(true);
    await wifiScanReqC!.write([1], withoutResponse: false);
  }

  void addDemoData() {
    setState(() {
      mockGateways = [
        MockGateway('ESP32-Gateway DEMO (ID 80A5CC)', -66, 'AA:BB:CC:DD:EE:FF'),
        MockGateway('ESP32-Gateway DEMO-B (ID 123456)', -72, '11:22:33:44:55:66'),
      ];
      wifiNets = [
        // Fuertes
        WifiNet('Casa', -35, true),
        WifiNet('MiRed 5G', -58, true),
        // Medias
        WifiNet('MiRed 2.4G', -62, true),
        WifiNet('IoT-Lab', -48, true),
        // Débiles
        WifiNet('Café Libre', -67, false),
        WifiNet('Biblioteca', -73, true),
        WifiNet('Oficina-Guest', -82, false),
        // SSID oculto
        WifiNet('', -78, true),
        // Muy débil / abierto
        WifiNet('OpenNet', -90, false),
      ];
      wifiNets.sort((a, b) => b.rssi.compareTo(a.rssi));
    });
  }
  void chooseNetwork(WifiNet n) {
    setState(() {
      ssidCtrl.text = n.ssid;
      passEnabled = n.secure;
      if (!n.secure) passCtrl.clear();
    });
    if (n.ssid.isEmpty) {
      ssidFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Red oculta: ingresá el SSID manualmente')),
      );
    } else if (n.secure) {
      FocusScope.of(context).requestFocus(passFocus);
    } else {
      FocusScope.of(context).unfocus();
    }
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
    ssidFocus.dispose();
    wifiScanSub?.cancel();
    wifiScanTimeout?.cancel();
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: scanAndConnect,
              child: const Text('Buscar gateways (BLE)'),
            ),
            const SizedBox(height: 8),
            if (!kReleaseMode) ...[
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
            ],
            const SizedBox(height: 8),
            if (isScanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Gateways cercanos', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: gateways.length + (kReleaseMode ? 0 : mockGateways.length),
                itemBuilder: (context, i) {
                  if (i < gateways.length) {
                    final r = gateways[i];
                    final name = (r.device.platformName.isNotEmpty == true)
                        ? r.device.platformName
                        : (r.device.advName ?? 'ESP32-Gateway');
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.router, color: _wifiColor(r.rssi)),
                        title: Text(name ?? 'ESP32-Gateway'),
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
                        leading: Icon(Icons.router, color: _wifiColor(m.rssi)),
                        title: Text(m.name),
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
                        'Conectado a: ${connectedName.isNotEmpty ? connectedName : 'ESP32-Gateway'}',
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
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _statusColor(),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Estado: $statusText'),
            ),
            const SizedBox(height: 8),
            Text('Wi‑Fi pkts: $wifiPackets'),
            Text('Último: ${lastWifiPacket.isEmpty ? '-' : lastWifiPacket}'),
            const SizedBox(height: 12),
            const SizedBox(height: 8),
            TextField(
              controller: ssidCtrl,
              focusNode: ssidFocus,
              decoration: const InputDecoration(labelText: 'SSID'),
            ),
            TextField(
              controller: passCtrl,
              focusNode: passFocus,
              enabled: passEnabled,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: passEnabled ? null : 'Red abierta: no requiere contraseña',
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
            // Sección de redes WiFi escaneadas por el gateway (BLE)
            if (device != null || wifiNets.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Redes WiFi cercanas', style: TextStyle(fontWeight: FontWeight.w600)),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: (wifiScanReqC != null && !wifiScanning) ? scanWifi : null,
                        icon: const Icon(Icons.wifi_find),
                        label: Text(wifiScanning ? 'Buscando...' : 'Buscar redes'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: (wifiScanResC != null) ? () => wifiScanResC!.setNotifyValue(true) : null,
                        icon: const Icon(Icons.sync),
                        label: const Text('Reiniciar notif.'),
                      ),
                    ],
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
                            WifiStrengthIcon(rssi: n.rssi, size: 20),
                            const SizedBox(width: 4),
                            Icon(n.secure ? Icons.lock : Icons.lock_open, size: 16, color: Colors.grey[700]),
                          ],
                        ),
                        title: Text(n.ssid.isNotEmpty ? n.ssid : '<SSID oculto>'),
                        selected: ssidCtrl.text == n.ssid,
                        selectedTileColor: Color(0xFFE8F5E9),
                         trailing: TextButton(
                          onPressed: () => chooseNetwork(n),
                           child: const Text('Elegir'),
                         ),
                        onTap: () => chooseNetwork(n),
                       ),
                     );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ]
          ],
        ),
      ),
    ),
    );
  }
}

// Ícono WiFi con contorno + relleno por barras (0–4)
class WifiStrengthIcon extends StatelessWidget {
  final int rssi;
  final double size;
  final Color outlineColor;
  final Color fillColor;
  const WifiStrengthIcon({
    super.key,
    required this.rssi,
    this.size = 20,
    this.outlineColor = const Color(0xFF616161),
    this.fillColor = const Color(0xFF212121),
  });

  int _rssiToLevel(int rssi) {
    const int min = -90;
    const int max = -55;
    int v = rssi < min ? min : (rssi > max ? max : rssi);
    int pct = (((v - min) * 100) ~/ (max - min));
    if (pct <= 0) return 0;
    if (pct <= 40) return 1;
    if (pct <= 70) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final level = _rssiToLevel(rssi);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WifiPainter(level, outlineColor, fillColor),
      ),
    );
  }
}

class _WifiPainter extends CustomPainter {
  final int level;
  final Color outline;
  final Color fill;
  _WifiPainter(this.level, this.outline, this.fill);

  @override
   void paint(Canvas canvas, Size size) {
     final center = Offset(size.width / 2, size.height * 0.88);
     // Recorte de ángulo tipo Wi‑Fi: no dibujar semicirculo completo
     const trim = 0.18 * math.pi; // ~32° por lado
     final startAngle = math.pi + trim;
     final sweep = math.pi - 2 * trim; // ~116°
 
     final outlinePaint = Paint()
       ..style = PaintingStyle.stroke
       ..strokeWidth = size.width * 0.08
       ..strokeCap = StrokeCap.round
       ..color = outline;
 
     final fillPaint = Paint()
       ..style = PaintingStyle.stroke
       ..strokeWidth = size.width * 0.08
       ..strokeCap = StrokeCap.round
       ..color = fill;
 
     // Tres arcos en vez de cuatro, espaciados uniformemente
     final radii = [
       size.width * 0.28,
       size.width * 0.42,
       size.width * 0.56,
     ];
 
     for (int i = 0; i < radii.length; i++) {
       final rect = Rect.fromCircle(center: center, radius: radii[i]);
       canvas.drawArc(rect, startAngle, sweep, false, outlinePaint);
       if (i + 1 <= level) {
         canvas.drawArc(rect, startAngle, sweep, false, fillPaint);
       }
     }
   }

  @override
  bool shouldRepaint(covariant _WifiPainter old) {
    return old.level != level || old.outline != outline || old.fill != fill;
  }
}