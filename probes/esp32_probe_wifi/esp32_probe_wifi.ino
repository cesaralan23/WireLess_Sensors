#include <Arduino.h>
#include <WiFi.h>

void setup() {
  Serial.begin(115200);
  Serial.println("WIFI_PROBE: start");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true);
  WiFi.setSleep(true);
  Serial.printf("WIFI_PROBE: MAC=%s\n", WiFi.macAddress().c_str());
  Serial.println("WIFI_PROBE: setup done");
}

void loop() {
  Serial.println("WIFI_PROBE: alive");
  delay(2000);
}