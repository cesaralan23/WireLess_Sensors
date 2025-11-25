import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE UUIDs usados por el gateway ESP32 para provisión Wi‑Fi
class BleUuids {
  static final Guid provService = Guid("fefefefe-1234-5678-9abc-def012345678");
  static final Guid ssidChar = Guid("fefefefe-1234-5678-9abc-def012345679");
  static final Guid passChar = Guid("fefefefe-1234-5678-9abc-def01234567a");
  static final Guid applyChar = Guid("fefefefe-1234-5678-9abc-def01234567b");
  static final Guid statusChar = Guid("fefefefe-1234-5678-9abc-def01234567c");
  static final Guid wifiScanReqChar = Guid("fefefefe-1234-5678-9abc-def01234567e");
  static final Guid wifiScanResChar = Guid("fefefefe-1234-5678-9abc-def01234567f");
  // Método alternativo (pull): COUNT/IDX/ITEM
  static final Guid wifiScanCountChar = Guid("fefefefe-1234-5678-9abc-def012345680");
  static final Guid wifiScanIdxChar = Guid("fefefefe-1234-5678-9abc-def012345681");
  static final Guid wifiScanItemChar = Guid("fefefefe-1234-5678-9abc-def012345682");
  static final Guid deviceIdChar = Guid("fefefefe-1234-5678-9abc-def01234567d");
}