PROJECT NOTES — esp32-ble-wifi-provisioner

Estado: prototipo (binario Service Data, rotación OLED)

Decisiones principales:
- Se eligió Service Data binario (UUID 4fafc201-...) para prototipado por ser compacto y sin Company ID.
- Payload v1 (7 bytes): ver(1) | sensorId(2 LE) | temp_x10 (int16 LE) | hum_x10 (uint16 LE).
- `sensorId` se deriva automáticamente desde la MAC del ESP32 (últimos 2 bytes) para unicidad sin provisión manual.
- En el gateway, las pantallas OLED se crean dinámicamente según los sensores detectados; el usuario puede rotar con botones (GPIO13 izquierda, GPIO0 derecha).
- Se mantiene un fallback ASCII (manufacturerData) por compatibilidad con dispositivos antiguos.

Cambios realizados en esta sesión:
- `esp32_sensor/esp32_sensor.ino` -> ahora emite Service Data binario v1 (7 bytes) y deep sleep.
- `esp32_gateway/esp32_gateway.ino` -> parseo de Service Data binario; mapa de sensores; rotación de pantallas y auto-rotación; botones GPIO13/GPIO0; mutex para sincronización; web root muestra listado de sensores.
- `README.md` -> documentación del formato binario y del comportamiento de botones/OLED.

Decisiones recientes (confirmadas por el usuario):
- Mantener `GPIO0` como botón derecho y con funcionalidad de long-press para reset de WiFi. El usuario confirmó que no habrá problema con el uso de `GPIO0` durante el arranque porque no iniciará la placa con un cambio de pantalla forzado.
- Posponer la implementación de la "vinculación" (pairing) de sensores con el gateway: no se implementa ahora para no complicar pruebas rápidas. La vinculación podrá añadirse más adelante mediante uno de los métodos propuestos (modo pair en gateway o provisión desde la app).
 - Cambiar el pin del swordprobe del `GPIO27` (ADC2) al `GPIO32` (ADC1) para garantizar lecturas estables sin conflicto con BLE/WiFi. El botón de mantenimiento/wake permanece en `GPIO33` (RTC IO).

Ideas y próximos pasos:
- Vinculación (pairing) de sensores con gateway (pospuesto): opciones futuras:
  - Opción A: modo "pair" en el gateway que registra sensorIds recibidos durante un intervalo y los guarda en `Preferences`.
  - Opción B: la app Flutter envía una lista de `sensorId` al gateway vía la característica de provisión BLE y el gateway la persiste.
- Persistir la lista de sensores "vinculados" en `Preferences` para que sobreviva reinicios (útil si se decide implementar pairing).
- Auto-rotación de pantallas: implementada (intervalo por defecto `5s`). Se puede desactivar o ajustar en `esp32_gateway.ino` cambiando `AUTO_ROTATE_SECONDS`.
- Añadir CRC8 optativo al payload para detectar corrupción (añade 1 byte al payload).
- Dashboard backend (futuro): gateway puede reenviar lecturas vía MQTT/HTTP a un servidor con autenticación.

Registro de cambios (cronológico):
- [now] Migrado a Service Data binario v1; gateway muestra múltiples sensores y permite rotar pantallas con botones; decisión tomada de mantener GPIO0 y posponer vinculación.

Notas de testing:
- Monitorear puerto serie del gateway; se imprimen los Service Data recibidos en hex para depuración.
- Verificar que los sensores envían el payload correcto con `arduino-cli monitor`.