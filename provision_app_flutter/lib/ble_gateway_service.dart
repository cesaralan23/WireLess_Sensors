import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_uuids.dart';

/// Servicio que encapsula la lógica BLE del Gateway
class BleGatewayService {
  BluetoothDevice? device;

  BluetoothCharacteristic? ssidC;
  BluetoothCharacteristic? passC;
  BluetoothCharacteristic? applyC;
  BluetoothCharacteristic? statusC;
  BluetoothCharacteristic? wifiScanReqC;
  BluetoothCharacteristic? wifiScanResC;
  // Método alternativo (pull)
  BluetoothCharacteristic? wifiScanCountC;
  BluetoothCharacteristic? wifiScanIdxC;
  BluetoothCharacteristic? wifiScanItemC;
  BluetoothCharacteristic? deviceIdC;

  StreamSubscription<List<int>>? _statusSub;
  StreamSubscription<List<int>>? _wifiScanSub;
  // Callbacks almacenados para rearmar suscripciones
  void Function(String)? _onStatusCb;
  void Function(String)? _onWifiPacketCb;
  // Fallback: temporizador de lecturas periódicas del characteristic Wi‑Fi
  Timer? _wifiPollTimer;
  // Doble suscripción: stream value y onValueReceived
  StreamSubscription<List<int>>? _wifiScanSubValue;
  StreamSubscription<List<int>>? _wifiScanSubReceive;

  bool get isConnected => device != null;
  bool get canWifiScan => wifiScanReqC != null && (wifiScanResC != null || (wifiScanCountC != null && wifiScanIdxC != null && wifiScanItemC != null));

  Future<List<ScanResult>> scanGateways({bool filterPrefix = true, Duration timeout = const Duration(seconds: 8)}) async {
    final List<ScanResult> snapshot = [];
    final sub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) {
        final advName = r.advertisementData.advName;
        final hasService = r.advertisementData.serviceUuids.contains(BleUuids.provService.str128);
        final nameMatch = advName != null && advName.toUpperCase().startsWith("ESP32-GATEWAY");
        return hasService || (filterPrefix ? nameMatch : true);
      }).toList();
      snapshot
        ..clear()
        ..addAll(filtered);
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    // No detengas el escaneo inmediatamente: espera al menos el tiempo de timeout
    await Future.delayed(timeout);
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub.cancel();
    return snapshot;
  }

  // Nuevo: escaneo con actualización incremental del listado
  Future<void> scanGatewaysLive({
    bool filterPrefix = true,
    Duration timeout = const Duration(seconds: 8),
    required void Function(List<ScanResult> results) onUpdate,
  }) async {
    final List<ScanResult> snapshot = [];
    final sub = FlutterBluePlus.scanResults.listen((results) {
      final filtered = results.where((r) {
        final advName = r.advertisementData.advName;
        final hasService = r.advertisementData.serviceUuids.contains(BleUuids.provService.str128);
        final nameMatch = advName != null && advName.toUpperCase().startsWith("ESP32-GATEWAY");
        return hasService || (filterPrefix ? nameMatch : true);
      }).toList();
      snapshot
        ..clear()
        ..addAll(filtered);
      onUpdate(List<ScanResult>.from(snapshot));
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    await Future.delayed(timeout);
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await sub.cancel();
  }

  Future<void> connectTo(
    BluetoothDevice d, {
    required void Function(String status) onStatus,
    required void Function(String deviceId) onDeviceId,
    required void Function(String wifiPacket) onWifiPacket,
  }) async {
    device = d;
    _onStatusCb = onStatus;
    _onWifiPacketCb = onWifiPacket;

    await device!.connect();
    // Pequeña espera para evitar problemas de caché/descubrimiento en Android
    await Future.delayed(const Duration(milliseconds: 500));

    // MTU sólo Android, kIsWeb no soporta
    if (!kIsWeb && await FlutterBluePlus.adapterName == "Android") {
      try {
        await device!.requestMtu(185);
      } catch (_) {}
    }

    final services = await device!.discoverServices();
    BluetoothService? prov;
    try {
      prov = services.firstWhere((s) => s.uuid == BleUuids.provService);
    } catch (_) {
      prov = null;
    }

    ssidC = _findChar(prov, BleUuids.ssidChar);
    passC = _findChar(prov, BleUuids.passChar);
    applyC = _findChar(prov, BleUuids.applyChar);
    statusC = _findChar(prov, BleUuids.statusChar);
    wifiScanReqC = _findChar(prov, BleUuids.wifiScanReqChar);
    wifiScanResC = _findChar(prov, BleUuids.wifiScanResChar);
    // Pull
    wifiScanCountC = _findChar(prov, BleUuids.wifiScanCountChar);
    wifiScanIdxC = _findChar(prov, BleUuids.wifiScanIdxChar);
    wifiScanItemC = _findChar(prov, BleUuids.wifiScanItemChar);
    deviceIdC = _findChar(prov, BleUuids.deviceIdChar);

    if (statusC != null) {
      await statusC!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 200));
      _statusSub = statusC!.onValueReceived.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onStatusCb;
        if (cb != null) cb(txt);
      });
    }

    if (wifiScanResC != null) {
      await wifiScanResC!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 200));
      try { await _wifiScanSub?.cancel(); } catch (_) {}
      try { await _wifiScanSubValue?.cancel(); } catch (_) {}
      try { await _wifiScanSubReceive?.cancel(); } catch (_) {}
      // Escuchar cambios de valor (notify/indicate/read)
      _wifiScanSubValue = wifiScanResC!.value.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      // También escuchar por onValueReceived
      _wifiScanSubReceive = wifiScanResC!.onValueReceived.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      // Lectura inicial para primar el stream
      try {
        final priming = await wifiScanResC!.read();
        final txt = utf8.decode(priming, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null && txt.isNotEmpty) cb(txt);
      } catch (_) {}
    }

    if (deviceIdC != null) {
      try {
        final idData = await deviceIdC!.read();
        final idTxt = utf8.decode(idData, allowMalformed: true);
        onDeviceId(idTxt);
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    try { await _wifiScanSub?.cancel(); } catch (_) {}
    try { await _wifiScanSubValue?.cancel(); } catch (_) {}
    try { await _wifiScanSubReceive?.cancel(); } catch (_) {}
    try { await _statusSub?.cancel(); } catch (_) {}
    try { _wifiPollTimer?.cancel(); } catch (_) {}

    try { await device?.disconnect(); } catch (_) {}

    device = null;
    ssidC = null;
    passC = null;
    applyC = null;
    statusC = null;
    wifiScanReqC = null;
    wifiScanResC = null;
    wifiScanCountC = null;
    wifiScanIdxC = null;
    wifiScanItemC = null;
    deviceIdC = null;
    _onStatusCb = null;
    _onWifiPacketCb = null;
    _wifiPollTimer = null;
    _wifiScanSub = null;
    _wifiScanSubValue = null;
    _wifiScanSubReceive = null;
  }

  Future<void> scanWifi() async {
    // Si por caché GATT aún no están, reintenta descubrir el servicio
    if (device != null && (wifiScanReqC == null || (wifiScanResC == null && (wifiScanCountC == null || wifiScanIdxC == null || wifiScanItemC == null)))) {
      try {
        await Future.delayed(const Duration(milliseconds: 300));
        final services = await device!.discoverServices();
        BluetoothService? prov;
        try { prov = services.firstWhere((s) => s.uuid == BleUuids.provService); } catch (_) { prov = null; }
        wifiScanReqC = _findChar(prov, BleUuids.wifiScanReqChar);
        wifiScanResC = _findChar(prov, BleUuids.wifiScanResChar);
        wifiScanCountC = _findChar(prov, BleUuids.wifiScanCountChar);
        wifiScanIdxC = _findChar(prov, BleUuids.wifiScanIdxChar);
        wifiScanItemC = _findChar(prov, BleUuids.wifiScanItemChar);
      } catch (_) {}
    }

    // Preferir método pull si está disponible
    if (wifiScanReqC != null && wifiScanCountC != null && wifiScanIdxC != null && wifiScanItemC != null) {
      await scanWifiPull();
      return;
    }

    // Fallback: método push por notificación
    if (wifiScanResC != null) {
      await wifiScanResC!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 100));
      try { await _wifiScanSub?.cancel(); } catch (_) {}
      try { await _wifiScanSubValue?.cancel(); } catch (_) {}
      try { await _wifiScanSubReceive?.cancel(); } catch (_) {}
      _wifiScanSubValue = wifiScanResC!.value.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      _wifiScanSubReceive = wifiScanResC!.onValueReceived.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      // Lectura inicial para primar el stream
      try {
        final priming = await wifiScanResC!.read();
        final txt = utf8.decode(priming, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null && txt.isNotEmpty) cb(txt);
      } catch (_) {}
    }
    if (wifiScanReqC != null) {
      await wifiScanReqC!.write([1]);
      // Iniciar fallback de lectura periódica por si las notificaciones no llegan
      _startWifiPoll(interval: const Duration(milliseconds: 250), max: const Duration(seconds: 12));
    }
  }

  Future<void> ensureWifiNotify() async {
    if (wifiScanResC != null) {
      await wifiScanResC!.setNotifyValue(true);
      await Future.delayed(const Duration(milliseconds: 100));
      try { await _wifiScanSub?.cancel(); } catch (_) {}
      try { await _wifiScanSubValue?.cancel(); } catch (_) {}
      try { await _wifiScanSubReceive?.cancel(); } catch (_) {}
      _wifiScanSubValue = wifiScanResC!.value.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      _wifiScanSubReceive = wifiScanResC!.onValueReceived.listen((data) {
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null) cb(txt);
      });
      // Lectura inicial para primar el stream
      try {
        final priming = await wifiScanResC!.read();
        final txt = utf8.decode(priming, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null && txt.isNotEmpty) cb(txt);
      } catch (_) {}
    }
  }

  Future<void> scanWifiPull() async {
    if (wifiScanReqC == null || wifiScanCountC == null || wifiScanIdxC == null || wifiScanItemC == null) return;

    // Solicitar escaneo
    await wifiScanReqC!.write([1]);

    // Esperar COUNT
    int count = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final data = await wifiScanCountC!.read();
        final txt = utf8.decode(data, allowMalformed: true).trim();
        if (txt.isNotEmpty) {
          final maybe = int.tryParse(txt);
          if (maybe != null) {
            count = maybe;
            break;
          }
        }
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Si no hay redes, enviar END
    if (count <= 0) {
      final cb = _onWifiPacketCb;
      if (cb != null) cb('END');
      return;
    }

    // Leer cada ITEM por índice (robusto: reintentos de lectura)
    for (int i = 0; i < count; i++) {
      try {
        await wifiScanIdxC!.write(utf8.encode(i.toString()));
        String txt = '';
        // Hasta 5 intentos para obtener ITEM no vacío
        for (int tries = 0; tries < 5; tries++) {
          final data = await wifiScanItemC!.read();
          if (data.isNotEmpty) {
            txt = utf8.decode(data, allowMalformed: true).replaceAll('\u0000', '').trim();
            if (txt.isNotEmpty && txt != 'ERR') break;
          }
          await Future.delayed(const Duration(milliseconds: 60));
        }
        final cb = _onWifiPacketCb;
        if (cb != null && txt.isNotEmpty && txt != 'ERR') cb(txt);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 60));
    }

    // Señal de fin
    final cb = _onWifiPacketCb;
    if (cb != null) cb('END');
  }

  Future<void> apply(String ssid, String pass) async {
    if (ssidC == null || passC == null || applyC == null) return;
    await ssidC!.write(utf8.encode(ssid));
    await passC!.write(utf8.encode(pass));
    await applyC!.write([1]);
  }

  BluetoothCharacteristic? _findChar(BluetoothService? service, Guid uuid) {
    try {
      if (service == null) return null;
      return service.characteristics.firstWhere((c) => c.uuid == uuid);
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await _wifiScanSub?.cancel();
    await _wifiScanSubValue?.cancel();
    await _wifiScanSubReceive?.cancel();
    await _statusSub?.cancel();
    try { _wifiPollTimer?.cancel(); } catch (_) {}
  }

  void _startWifiPoll({required Duration interval, required Duration max}) {
    try { _wifiPollTimer?.cancel(); } catch (_) {}
    if (wifiScanResC == null) return;

    final endInstant = DateTime.now().add(max);
    _wifiPollTimer = Timer.periodic(interval, (t) async {
      // Parar por tiempo
      if (DateTime.now().isAfter(endInstant)) {
        try { t.cancel(); } catch (_) {}
        return;
      }
      try {
        final data = await wifiScanResC!.read();
        if (data.isEmpty) return;
        final txt = utf8.decode(data, allowMalformed: true);
        final cb = _onWifiPacketCb;
        if (cb != null && txt.isNotEmpty) cb(txt);
        // Parar si el firmware envía END
        if (txt.trim() == 'END') {
          try { t.cancel(); } catch (_) {}
        }
      } catch (_) {}
    });
  }
}