import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:io' show Platform;
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:provision_app_flutter/ble_uuids.dart';
import 'package:provision_app_flutter/ble_gateway_service.dart';
import 'package:provision_app_flutter/widgets.dart';
import 'package:provision_app_flutter/gateway_pages.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:provision_app_flutter/provision_guide_page.dart';

// UUIDs del servicio/ características (deben coincidir con el ESP32)
final Guid provService = Guid("fefefefe-1234-5678-9abc-def012345678");
final Guid ssidChar = Guid("fefefefe-1234-5678-9abc-def012345679");
final Guid passChar = Guid("fefefefe-1234-5678-9abc-def01234567a");
final Guid applyChar = Guid("fefefefe-1234-5678-9abc-def01234567b");
final Guid statusChar = Guid("fefefefe-1234-5678-9abc-def01234567c");
final Guid deviceIdChar = Guid("fefefefe-1234-5678-9abc-def01234567d");
final Guid wifiScanReqChar = Guid("fefefefe-1234-5678-9abc-def01234567e");
final Guid wifiScanResChar = Guid("fefefefe-1234-5678-9abc-def01234567f");

enum ProvisionStatus {
  idle,
  awaiting,
  connecting,
  success,
  fail,
  permissionDenied,
  connectError,
  bluetoothOff,
  scanError,
}

String statusLabel(ProvisionStatus s) {
  switch (s) {
    case ProvisionStatus.awaiting:
      return 'awaiting';
    case ProvisionStatus.connecting:
      return 'connecting';
    case ProvisionStatus.success:
      return 'success';
    case ProvisionStatus.fail:
      return 'fail';
    case ProvisionStatus.permissionDenied:
      return 'permission_denied';
    case ProvisionStatus.connectError:
      return 'connect_error';
    case ProvisionStatus.bluetoothOff:
      return 'bluetooth_off';
    case ProvisionStatus.scanError:
      return 'scan_error';
    case ProvisionStatus.idle:
    default:
      return 'idle';
  }
}

Color statusColor(ProvisionStatus s) {
  switch (s) {
    case ProvisionStatus.awaiting:
      return Colors.amber.shade200;
    case ProvisionStatus.connecting:
      return Colors.blue.shade200;
    case ProvisionStatus.success:
      return Colors.green.shade300;
    case ProvisionStatus.fail:
      return Colors.red.shade300;
    case ProvisionStatus.permissionDenied:
      return Colors.grey.shade300;
    case ProvisionStatus.connectError:
      return Colors.orange.shade300;
    case ProvisionStatus.bluetoothOff:
      return Colors.grey.shade300;
    case ProvisionStatus.scanError:
      return Colors.orange.shade200;
    case ProvisionStatus.idle:
    default:
      return Colors.grey.shade200;
  }
}

ProvisionStatus parseStatusText(String txt) {
  switch (txt.trim().toLowerCase()) {
    case 'idle':
      return ProvisionStatus.idle;
    case 'awaiting':
      return ProvisionStatus.awaiting;
    case 'connecting':
      return ProvisionStatus.connecting;
    case 'success':
      return ProvisionStatus.success;
    case 'fail':
      return ProvisionStatus.fail;
    default:
      return ProvisionStatus.idle;
  }
}

class WifiNet {
  final String ssid;
  final int rssi;
  final bool secure;
  WifiNet(this.ssid, this.rssi, this.secure);
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
      const GatewaysPage(),
      const ProvisionGuidePage(),
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

  // Servicio BLE modularizado
  final BleGatewayService ble = BleGatewayService();

  final ssidCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final passFocus = FocusNode();
  final ssidFocus = FocusNode();
  ProvisionStatus status = ProvisionStatus.idle;
  String? statusMsg;
  List<ScanResult> gateways = [];
  bool isScanning = false;
  String connectedName = '';
  String gatewayIdText = '';
  bool filterPrefix = true;
  bool showPass = false;
  bool applyBusy = false;
  bool passEnabled = true;
  bool isBluetoothOn = false;
  StreamSubscription<BluetoothAdapterState>? adapterStateSub;

  List<WifiNet> wifiNets = [];
  bool wifiScanning = false;
  StreamSubscription<List<int>>? wifiScanSub;
  Timer? wifiScanTimeout;
  int wifiPackets = 0;
  String lastWifiPacket = '';
  // NUEVO: suscripción para el characteristic de estado
  StreamSubscription<List<int>>? statusSub;

  Color _statusColor() {
    return statusColor(status);
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

  Future<bool> _ensureBluetoothOn() async {
    if (!Platform.isAndroid) return true;

    // Usa el estado cacheado primero; si está apagado, muestra el diálogo
    if (!isBluetoothOn) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Activar Bluetooth'),
          content: const Text('Para buscar gateways, activa el Bluetooth del teléfono.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                if (!kIsWeb && Platform.isAndroid) {
                  try {
                    final intent = const AndroidIntent(
                      action: 'android.bluetooth.adapter.action.REQUEST_ENABLE',
                    );
                    await intent.launch();
                  } catch (_) {}
                }
              },
              child: const Text('Activar Bluetooth'),
            ),
          ],
        ),
      );

      // Espera a que se active
      try {
        final on = await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 8));
        return on == BluetoothAdapterState.on;
      } catch (_) {
        return false;
      }
    }

    // Si el cache dice que está encendido, valida con el stream
    try {
      final s = await FlutterBluePlus.adapterState.first;
      return s == BluetoothAdapterState.on;
    } catch (_) {
      return isBluetoothOn; // mejor esfuerzo
    }
  }

  Future<void> scanAndConnect({bool filterPrefix = true}) async {
    setState(() {
      isScanning = true;
      gateways = [];
      status = ProvisionStatus.idle;
      statusMsg = null;
    });
    await _ensureBlePermissions();
    final ok = await _ensureBluetoothOn();
    if (!ok) {
      setState(() {
        isScanning = false;
      });
      return;
    }

    try {
      await ble.scanGatewaysLive(
        filterPrefix: filterPrefix,
        timeout: const Duration(seconds: 8),
        onUpdate: (results) {
          setState(() {
            gateways = results;
          });
        },
      );
    } catch (e) {
      setState(() {
        status = ProvisionStatus.scanError;
        statusMsg = '$e';
      });
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> connectTo(BluetoothDevice d) async {
    setState(() {
      connectedName = d.platformName.isNotEmpty
          ? d.platformName
          : (d.advName.isNotEmpty ? d.advName : d.remoteId.str);
    });

    await ble.connectTo(
      d,
      onStatus: (txt) {
        final st = parseStatusText(txt);
        setState(() {
          status = st;
          statusMsg = null;
          // No finalizar escaneo WiFi por estados generales; esperamos 'END' o timeout
        });
      },
      onDeviceId: (idTxt) {
        setState(() {
          gatewayIdText = idTxt;
        });
      },
      onWifiPacket: (txt) {
        setState(() {
          wifiPackets += 1;
          lastWifiPacket = txt;
        });
        // Sanitizar posibles bytes de control/NUL y espacios
        final s = txt.replaceAll('\u0000', '').trim();
        if (s == 'END') {
          setState(() {
            wifiScanning = false;
          });
          return;
        }
        final parts = s.split('|');
        if (parts.length >= 3) {
          final ssid = parts[0];
          final rssi = int.tryParse(parts[1].trim()) ?? -100;
          final secure = parts[2].trim() != '0';
          final net = WifiNet(ssid, rssi, secure);
          setState(() {
            // deduplicar por SSID
            final existing = wifiNets.indexWhere((n) => n.ssid == ssid);
            if (existing >= 0) {
              wifiNets[existing] = net;
            } else {
              wifiNets.add(net);
            }
            wifiNets.sort((a, b) => b.rssi.compareTo(a.rssi));
          });
        }
      },
    );
  }

  Future<void> disconnect() async {
    await ble.disconnect();
    setState(() {
      connectedName = '';
      gatewayIdText = '';
      status = ProvisionStatus.idle;
      statusMsg = null;
      wifiPackets = 0;
      lastWifiPacket = '';
      wifiNets.clear();
    });
  }

  Future<void> scanWifi() async {
    setState(() {
      wifiScanning = true;
      wifiPackets = 0;
      lastWifiPacket = '';
      wifiNets.clear();
    });

    await ble.ensureWifiNotify();
    await ble.scanWifi();

    wifiScanTimeout?.cancel();
    wifiScanTimeout = Timer(const Duration(seconds: 10), () {
      setState(() {
        wifiScanning = false;
      });
    });
  }

  Future<void> scanWifiPhone() async {
    setState(() {
      wifiScanning = true;
      wifiPackets = 0;
      lastWifiPacket = 'phone-scan';
      wifiNets.clear();
    });

    try {
      // Pedir permisos de ubicación / nearby wifi si están disponibles
      try {
        await [
          Permission.locationWhenInUse,
          Permission.location,
          Permission.nearbyWifiDevices,
        ].request();
      } catch (_) {}

      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan != CanStartScan.yes) {
        setState(() {
          wifiScanning = false;
          statusMsg = 'Permisos/ubicación requeridos para escanear Wi‑Fi del teléfono';
        });
        return;
      }

      await WiFiScan.instance.startScan();
      await Future.delayed(const Duration(seconds: 2));

      final canGet = await WiFiScan.instance.canGetScannedResults();
      List<WiFiAccessPoint> aps = [];
      if (canGet == CanGetScannedResults.yes) {
        aps = await WiFiScan.instance.getScannedResults();
      }

      final seen = <String>{};
      final nets = <WifiNet>[];
      for (final ap in aps) {
        final ssid = ap.ssid ?? '';
        if (ssid.isEmpty || seen.contains(ssid)) continue;
        seen.add(ssid);
        final rssi = ap.level ?? -99;
        final caps = ap.capabilities ?? '';
        final secure = caps.contains('WEP') || caps.contains('WPA');
        nets.add(WifiNet(ssid, rssi, secure));
      }
      nets.sort((a, b) => b.rssi.compareTo(a.rssi));

      setState(() {
        wifiNets = nets;
        wifiScanning = false;
        statusMsg = nets.isEmpty ? 'Sin redes (teléfono)' : 'Usando redes del teléfono (' + nets.length.toString() + ')';
      });
    } catch (e) {
      setState(() {
        wifiScanning = false;
        statusMsg = 'Fallback Wi‑Fi teléfono falló: ' + e.toString();
      });
    }
  }

  Future<void> apply() async {
    setState(() {
      applyBusy = true;
    });
    try {
      await ble.apply(ssidCtrl.text.trim(), passCtrl.text.trim());
    } finally {
      setState(() {
        applyBusy = false;
      });
    }
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

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && Platform.isAndroid) {
      adapterStateSub = FlutterBluePlus.adapterState.listen((s) {
        final on = s == BluetoothAdapterState.on;
        setState(() {
          isBluetoothOn = on;
          if (!on && !isScanning) {
            status = ProvisionStatus.bluetoothOff;
            statusMsg = null;
          } else if (on && status == ProvisionStatus.bluetoothOff) {
            status = ProvisionStatus.idle;
            statusMsg = null;
          }
        });
      });
      FlutterBluePlus.adapterState.first.then((s) {
        final on = s == BluetoothAdapterState.on;
        setState(() => isBluetoothOn = on);
      }).catchError((_) {
        setState(() => isBluetoothOn = true);
      });
    }
  }

  @override
  void dispose() {
    wifiScanTimeout?.cancel();
    adapterStateSub?.cancel();
    ble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provisionar Gateway ESP32'),
        actions: [
          IconButton(
            tooltip: 'Refrescar escaneo',
            icon: const Icon(Icons.refresh),
            onPressed: (!isBluetoothOn || isScanning) ? null : () => scanAndConnect(filterPrefix: true),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            if (!isBluetoothOn)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Color(0xFFFFEEBA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bluetooth_disabled, color: Colors.orange),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Debes activar el Bluetooth para buscar gateways.')),
                    TextButton(
                      onPressed: () async {
                        if (!kIsWeb && Platform.isAndroid) {
                          try {
                            final intent = const AndroidIntent(
                              action: 'android.bluetooth.adapter.action.REQUEST_ENABLE',
                            );
                            await intent.launch();
                          } catch (_) {}
                        }
                      },
                      child: const Text('Activar'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: isBluetoothOn ? scanAndConnect : null,
              child: const Text('Buscar gateways (BLE)'),
            ),
            const SizedBox(height: 8),
            
            const SizedBox(height: 8),
            if (isScanning) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text('Gateways cercanos', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: gateways.length,
                itemBuilder: (context, i) {
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
                },
              ),
            ),
            const SizedBox(height: 8),
            if (!ble.isConnected)
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
                            onPressed: isScanning ? null : () => scanAndConnect(filterPrefix: true),
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
            CredentialsForm(
              ssidCtrl: ssidCtrl,
              passCtrl: passCtrl,
              ssidFocus: ssidFocus,
              passFocus: passFocus,
              passEnabled: passEnabled,
              showPass: showPass,
              applyBusy: applyBusy,
              isConnected: ble.isConnected,
              onToggleShowPass: () => setState(() => showPass = !showPass),
              onApply: () async {
                setState(() => applyBusy = true);
                await apply();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Credenciales enviadas. Verificando estado...')),
                  );
                }
                setState(() => applyBusy = false);
              },
              applyColor: statusColor(status),
            ),
            const SizedBox(height: 12),
            // Sección de redes WiFi escaneadas por el gateway (BLE)
            if (ble.isConnected || wifiNets.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Redes WiFi cercanas', style: TextStyle(fontWeight: FontWeight.w600)),
                  WifiControls(
                    canWifiScan: true,
                    wifiScanning: wifiScanning,
                    onScanWifi: scanWifiPhone,
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