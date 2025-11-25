#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>

Preferences prefs;

void TaskStub(void* pv) {
  const char* name = (const char*)pv;
  for (;;) {
    Serial.printf("%s: running\n", name);
    vTaskDelay(pdMS_TO_TICKS(2000));
  }
}

void setup() {
  Serial.begin(115200);
  Serial.println("STEP1: start");

  Serial.println("STEP1: prefs.begin");
  prefs.begin("wifi", false);
  String ssid = prefs.getString("ssid", "");
  Serial.printf("STEP1: prefs ssid_len=%d\n", ssid.length());

  Serial.println("STEP1: WiFi mode set");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);

  String mac = WiFi.macAddress();
  mac.replace(":","");
  String gatewayId = mac.substring(mac.length()-6);
  Serial.printf("STEP1: Gateway ID %s\n", gatewayId.c_str());

  Serial.println("STEP1: BLE init");
  BLEDevice::init((String("ESP32-Gateway-") + gatewayId).c_str());
  BLEDevice::setPower(ESP_PWR_LVL_P7);
  Serial.println("STEP1: BLE init done");

  Serial.println("STEP1: starting tasks");
  xTaskCreatePinnedToCore(TaskStub, "t1", 2048, (void*)"Task1", 1, NULL, 1);
  xTaskCreatePinnedToCore(TaskStub, "t2", 2048, (void*)"Task2", 1, NULL, 1);

  Serial.println("STEP1: setup done");
}

void loop() {
  Serial.println("STEP1: alive");
  delay(3000);
}