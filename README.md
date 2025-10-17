# ESP32 BLE WiFi Provisioner

Proyecto para provisionar gateways ESP32 vía BLE usando una app Flutter (Web/Android). Incluye firmware de gateway y app de provisión con escaneo WiFi.

## Componentes
- `esp32_gateway/`: firmware del gateway ESP32 (Arduino/ESP-IDF vía Arduino CLI)
- `provision_app_flutter/`: app Flutter para escanear gateways BLE, leer ID del dispositivo y enviar credenciales WiFi
- `esp32_sensor/`: ejemplo de sketch adicional (opcional)

## Características
- Provisión WiFi por BLE (SSID/Password)
- Escaneo de redes WiFi desde el gateway, con RSSI y “segura/abierta”
- Device ID expuesto por BLE y visible en la app
- UI/UX pensado para flujo rápido de escaneo, conexión y configuración

## Requisitos
- `arduino-cli` instalado (incluido en `tools/arduino-cli/`)
- Flutter estable (opcional para Web/Android; se usa local)
- ESP32 (WROOM/WROVER) conectado por USB

## Firmware (ESP32)
1. Abrir `esp32_gateway/esp32_gateway.ino`
2. Compilar y subir con Arduino CLI:
   ```powershell
   tools/arduino-cli/arduino-cli.exe compile -b esp32:esp32:esp32 --warnings all esp32_gateway
   tools/arduino-cli/arduino-cli.exe upload -b esp32:esp32:esp32 -p COM5 esp32_gateway
   ```
3. Monitorear serial para ver ID y estado:
   ```powershell
   tools/arduino-cli/arduino-cli.exe monitor -p COM5 -b esp32:esp32:esp32 --baud 115200
   ```

### BLE UUIDs (servicio de provisión)
- Servicio: `fefefefe-1234-5678-9abc-def012345678`
- `SSID` (write): `...679`
- `PASS` (write): `...67a`
- `APPLY` (write): `...67b`
- `STATUS` (notify): `...67c`
- `DEVICE_ID` (read): `...67d`
- `WIFI_SCAN_REQ` (write): `...67e`
- `WIFI_SCAN_RES` (notify): `...67f`

### Protocolo de escaneo WiFi
El gateway notifica cada red en texto `SSID|RSSI|SECURE`, y envía `END` al finalizar.
- `SECURE = '0'` -> abierta
- `SECURE != '0'` -> segura

## App Flutter
1. Entra a `provision_app_flutter`
2. Ejecuta el servidor web:
   ```powershell
   flutter.bat run -d web-server --web-port 5558
   ```
3. Abre el preview en `http://localhost:5558/`
4. Otorga permisos BLE en el navegador si te los solicita

## Demos
- Botón “Cargar demo UX” para insertar redes y gateways ficticios
- Botones para simular estados: `idle`, `awaiting`, `connecting`, `success`, `fail`

## Nombre del proyecto
Sugerencia de nombre: `esp32-ble-wifi-provisioner`
Otras opciones:
- `ble-provision-gateway`
- `gateway-ble-wifi`
- `provis-esp32`
- `Puente-BLE-WiFi`

## Licencia
Pendiente de decidir. Añadir una licencia si se publicará.