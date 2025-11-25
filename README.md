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

### Protocolo BLE del sensor (actual)
Se ha migrado a un payload binario en Service Data para prototipado. Detalles:

- Usamos Service Data con UUID: `4fafc201-1fb5-459e-8fcc-c5c9c331914b`
- Layout (Service Data, little-endian):
  - `ver` (1 byte) — versión del protocolo (0x01)
  - `sensorId` (2 bytes, uint16 LE) — ID único del sensor (derivado de la MAC, últimos 2 bytes)
  - `temp_x10` (int16 LE) — temperatura × 10 (permite negativos)
  - `hum_x10` (uint16 LE) — humedad × 10
- Total sin CRC: 7 bytes. Ejemplo: `01 C7 01 EA 00 C7 01` (v1, sensorId=0x01C7, T=23.4, H=45.5)

Ventajas:
- Muy compacto (7 bytes), robusto y eficiente en consumo.
- Fácil de parsear y versionar (campo `ver`).

Compatibilidad y fallback:
- El gateway detecta primero Service Data binario (v1) y lo parsea.
- Mantuvimos un fallback para `manufacturerData` ASCII por compatibilidad.

### Botones y OLED del gateway
- La OLED muestra una pantalla por sensor detectado; las pantallas se generan dinámicamente según los sensores vistos.
- Auto-rotación: la pantalla cambia automáticamente cada `5` segundos. Este intervalo se puede ajustar desde la interfaz web del gateway (o poner `0` para deshabilitar).
- Botones:
  - `GPIO13` — botón izquierdo: retrocede a la pantalla anterior (pulso corto).
  - `GPIO0`  — botón derecho: avanza a la siguiente pantalla (pulso corto). Si se mantiene presionado 3s en GPIO0, se resetean las credenciales WiFi guardadas.
- El gateway mantiene un mapa de sensores detectados y ordena las pantallas por último visto (más reciente primero).

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

## Notas de desarrollo (breve)
- Decidimos usar Service Data binario (v1) para prototipado: compacto y fácil de migrar.
- Sensor genera `sensorId` automáticamente desde la MAC (últimos 2 bytes). Para producción se puede provisionar un ID estable.
- En producción se puede usar Manufacturer Data si se registra un Company ID con Bluetooth SIG, pero no es necesario.

## Dependencias y compilación (sensor y gateway)

Librerías necesarias (instalar vía Library Manager o arduino-cli):
- `Adafruit_HTU21DF`
- `Adafruit_SSD1306`
- `Adafruit_GFX`

Instalar con `arduino-cli` (ejemplo):
```
tools/arduino-cli/arduino-cli.exe lib install "Adafruit HTU21DF Library"
tools/arduino-cli/arduino-cli.exe lib install "Adafruit SSD1306"
tools/arduino-cli/arduino-cli.exe lib install "Adafruit GFX Library"
```

Compilar y subir (ejemplos):
- Gateway (COM5):
  ```powershell
  tools/arduino-cli/arduino-cli.exe compile -b esp32:esp32:esp32 --warnings all esp32_gateway
  tools/arduino-cli/arduino-cli.exe upload -b esp32:esp32:esp32 -p COM5 esp32_gateway
  tools/arduino-cli/arduino-cli.exe monitor -p COM5 -b esp32:esp32:esp32 --baud 115200
  ```

- Sensor (COM3):
  ```powershell
  tools/arduino-cli/arduino-cli.exe compile -b esp32:esp32:esp32 --warnings all esp32_sensor
  tools/arduino-cli/arduino-cli.exe upload -b esp32:esp32:esp32 -p COM3 esp32_sensor
  tools/arduino-cli/arduino-cli.exe monitor -p COM3 -b esp32:esp32:esp32 --baud 115200
  ```

Notas:
- El sensor ahora anuncia en Service Data binario y luego entra en deep sleep para optimizar consumo.
- La OLED del gateway se encuentra en la dirección I2C por defecto `0x3C`.
- Para debug: mirar el monitor serie del gateway para ver Service Data recibidos en hex.

### Mapeo de pines (sensor)
- `GPIO32` — entrada del swordprobe (humedad del suelo). Elegido por ser `ADC1` y evitar conflictos con WiFi/BLE (no usar `ADC2` para lecturas analógicas si BLE/WiFi están activos).
- `GPIO33` — botón físico/RTC IO para wake/maintenance; permite despertar desde deep sleep por nivel.
- `GPIO21/22` — I2C del OLED (por defecto), no interferir con la señal del swordprobe.

Recomendaciones de conexión del swordprobe (a 3.3 V):
- `Vcc` → `3.3 V`, `GND` común con el ESP32.
- `Salida` → `GPIO32` pasando por `Rserie 1 kΩ` y filtro RC (`100 nF` a GND en el nodo) para reducir ruido.
- Si la salida fuera PWM/frecuencia, también puede leerse como digital y convertir con RC a voltaje medio si se prefiere ADC.