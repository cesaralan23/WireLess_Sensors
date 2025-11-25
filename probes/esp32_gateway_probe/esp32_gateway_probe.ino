#include <Arduino.h>
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>

const int LED_PIN = 2;

Preferences prefs;

void setup() {
  Serial.begin(115200);
  Serial.println("PROBE: setup start");
  pinMode(LED_PIN, OUTPUT);

  prefs.begin("wifi", false);
  Serial.println("PROBE: prefs.begin done");
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  Serial.printf("PROBE: prefs ssid='%s' pass_len=%d\n", ssid.c_str(), pass.length());

  WiFi.mode(WIFI_STA);
  Serial.println("PROBE: WiFi mode set");

  BLEDevice::init("ESP32-Probe");
  Serial.println("PROBE: BLE init done");

  digitalWrite(LED_PIN, HIGH);
  delay(200);
  digitalWrite(LED_PIN, LOW);
  Serial.println("PROBE: setup done");
}

void loop() {
  Serial.println("PROBE: alive");
  delay(2000);
}