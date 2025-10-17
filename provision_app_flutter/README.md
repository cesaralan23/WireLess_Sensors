Provisioning App (Flutter)

Resumen:
- App móvil sencilla para enviar SSID y Password al ESP32-Gateway por BLE.
- Usa el servicio BLE `fefefefe-1234-5678-9abc-def012345678` con características:
  - `SSID`  uuid: `fefefefe-1234-5678-9abc-def012345679` (WRITE/READ)
  - `PASS`  uuid: `fefefefe-1234-5678-9abc-def01234567a` (WRITE/READ)
  - `APPLY` uuid: `fefefefe-1234-5678-9abc-def01234567b` (WRITE)
  - `STATUS` uuid:`fefefefe-1234-5678-9abc-def01234567c` (READ/NOTIFY)

Pasos rápidos:
1) Instala Flutter y crea un proyecto vacío.
2) Añade dependencia `flutter_blue_plus` en `pubspec.yaml`.
3) Copia `lib/main.dart` de este ejemplo.
4) Compila en Android (iOS requiere permisos y adaptación de Info.plist).

Permisos Android:
- AndroidManifest.xml:
  - BLUETOOTH, BLUETOOTH_ADMIN, BLUETOOTH_CONNECT, BLUETOOTH_SCAN, ACCESS_FINE_LOCATION.

Flujo de uso:
- Pulsa "Buscar" para encontrar `ESP32-Gateway`.
- Escribe SSID y Password.
- Pulsa "Aplicar".
- Observa el STATUS: `connecting` → `success` o `fail`.