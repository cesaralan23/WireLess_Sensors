import 'package:flutter/material.dart';
import 'dart:async';

enum SensorType { soil, light, th }
enum SensorState { pending, assigned, ignored, blocked, offline }

class Gateway {
  final String id;
  final String name;
  final String location;
  Gateway({required this.id, required this.name, required this.location});
}

class Sensor {
  final String id;
  final SensorType type;
  String name;
  SensorState state;
  int rssi;
  DateTime? lastSeen;
  Sensor({
    required this.id,
    required this.type,
    required this.name,
    required this.state,
    required this.rssi,
    this.lastSeen,
  });
}

class DashboardController extends ChangeNotifier {
  final List<Gateway> gateways = [
    Gateway(id: 'gw-01', name: 'Gateway A', location: 'Rack 1'),
    Gateway(id: 'gw-02', name: 'Gateway B', location: 'Rack 2'),
  ];

  Gateway? selected;
  final List<Sensor> assigned = [];
  final List<Sensor> pending = [];
  final List<String> blockedIds = [];
  bool pairingWindowOpen = false;
  int pairingSecondsLeft = 0;
  Timer? _pairingTimer;
  Timer? _simulatorTimer;

  DashboardController() {
    selected = gateways.first;
    // Arranca con algunos sensores asignados de ejemplo
    assigned.addAll([
      Sensor(id: '0x3160', type: SensorType.soil, name: 'Suelo 1', state: SensorState.assigned, rssi: -45, lastSeen: DateTime.now()),
      Sensor(id: '0x21A3', type: SensorType.light, name: 'Luz 1', state: SensorState.assigned, rssi: -52, lastSeen: DateTime.now()),
    ]);
  }

  void openPairingWindow({int seconds = 30}) {
    pairingWindowOpen = true;
    pairingSecondsLeft = seconds;
    pending.clear();
    _pairingTimer?.cancel();
    _pairingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      pairingSecondsLeft--;
      if (pairingSecondsLeft <= 0) {
        closePairingWindow();
      } else {
        notifyListeners();
      }
    });
    _startSimulator();
    notifyListeners();
  }

  void closePairingWindow() {
    pairingWindowOpen = false;
    pairingSecondsLeft = 0;
    _pairingTimer?.cancel();
    _simulatorTimer?.cancel();
    notifyListeners();
  }

  void addSensor(Sensor s, {String? newName}) {
    s.state = SensorState.assigned;
    if (newName != null && newName.isNotEmpty) s.name = newName;
    // evitar duplicados
    if (!assigned.any((x) => x.id == s.id)) {
      assigned.add(s);
    }
    pending.removeWhere((x) => x.id == s.id);
    notifyListeners();
  }

  void ignoreSensor(Sensor s) {
    s.state = SensorState.ignored;
    pending.removeWhere((x) => x.id == s.id);
    notifyListeners();
  }

  void blockSensor(Sensor s) {
    s.state = SensorState.blocked;
    blockedIds.add(s.id);
    pending.removeWhere((x) => x.id == s.id);
    notifyListeners();
  }

  void deleteSensor(Sensor s) {
    assigned.removeWhere((x) => x.id == s.id);
    notifyListeners();
  }

  void updateSensorName(Sensor s, String newName) {
    s.name = newName.isNotEmpty ? newName : s.name;
    notifyListeners();
  }

  void addGateway(String name, String location, {String? id}) {
    final newId = id ?? 'gw-${(gateways.length + 1).toString().padLeft(2, '0')}';
    gateways.add(Gateway(id: newId, name: name, location: location));
    notifyListeners();
  }

  void removeGateway(String id) {
    gateways.removeWhere((g) => g.id == id);
    if (selected != null && selected!.id == id) {
      selected = gateways.isNotEmpty ? gateways.first : null;
    }
    notifyListeners();
  }

  IconData iconFor(SensorType t) {
    switch (t) {
      case SensorType.soil:
        return Icons.water_drop;
      case SensorType.light:
        return Icons.wb_sunny;
      case SensorType.th:
        return Icons.device_thermostat;
    }
  }

  Color colorFor(SensorType t) {
    switch (t) {
      case SensorType.soil:
        return const Color(0xFF2E7D32);
      case SensorType.light:
        return const Color(0xFFF9A825);
      case SensorType.th:
        return const Color(0xFF0288D1);
    }
  }

  Map<String, String> sampleDataFor(Sensor s) {
    switch (s.type) {
      case SensorType.soil:
        return {
          'Humedad (%)': (60 + (DateTime.now().second % 10)).toString(),
          'Voltaje (V)': '1.78',
        };
      case SensorType.light:
        return {
          'Luminosidad (lux)': (450 + (DateTime.now().second % 50)).toString(),
        };
      case SensorType.th:
        return {
          'Temperatura (°C)': (23.5 + (DateTime.now().second % 3) * 0.5).toStringAsFixed(1),
          'Humedad (%)': (56 + (DateTime.now().second % 5)).toString(),
        };
    }
  }

  void _startSimulator() {
    // Simula aparición de sensores en modo PAIR_REQ durante la ventana
    _simulatorTimer?.cancel();
    _simulatorTimer = Timer.periodic(const Duration(seconds: 3), (t) {
      if (!pairingWindowOpen) return;
      final samples = [
        Sensor(id: '0x90FE', type: SensorType.th, name: 'T/H 1', state: SensorState.pending, rssi: -40),
        Sensor(id: '0x3160', type: SensorType.soil, name: 'Suelo 2', state: SensorState.pending, rssi: -55),
        Sensor(id: '0x21A3', type: SensorType.light, name: 'Luz 2', state: SensorState.pending, rssi: -60),
      ];
      final s = samples[(DateTime.now().millisecondsSinceEpoch ~/ 3000) % samples.length];
      if (blockedIds.contains(s.id)) return;
      if (!pending.any((x) => x.id == s.id) && !assigned.any((x) => x.id == s.id)) {
        pending.add(s);
        notifyListeners();
      }
    });
  }
}