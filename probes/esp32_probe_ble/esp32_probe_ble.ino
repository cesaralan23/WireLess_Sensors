#include <Arduino.h>
#include <BLEDevice.h>

void setup() {
  Serial.begin(115200);
  Serial.println("BLE_PROBE: start");
  BLEDevice::init("ESP32-BLE-Probe");
  BLEDevice::setPower(ESP_PWR_LVL_P7);
  Serial.println("BLE_PROBE: init done");
}

void loop() {
  Serial.println("BLE_PROBE: alive");
  delay(2000);
}