#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>

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
  Serial.println("REDUCED: start");

  Serial.println("REDUCED: prefs.begin");
  prefs.begin("wifi", false);
  String ssid = prefs.getString("ssid", "");
  Serial.printf("REDUCED: prefs ssid_len=%d\n", ssid.length());

  Serial.println("REDUCED: WiFi mode set");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);

  String mac = WiFi.macAddress();
  mac.replace(":","");
  String gatewayId = mac.substring(mac.length()-6);
  Serial.printf("REDUCED: Gateway ID %s\n", gatewayId.c_str());

  Serial.println("REDUCED: BLE start (stub)");
  // BLEDevice::init etc omitted in reduced build

  Serial.println("REDUCED: starting tasks");
  xTaskCreatePinnedToCore(TaskStub, "t1", 2048, (void*)"Task1", 1, NULL, 1);
  xTaskCreatePinnedToCore(TaskStub, "t2", 2048, (void*)"Task2", 1, NULL, 1);

  Serial.println("REDUCED: setup done");
}

void loop() {
  Serial.println("REDUCED: alive");
  delay(3000);
}