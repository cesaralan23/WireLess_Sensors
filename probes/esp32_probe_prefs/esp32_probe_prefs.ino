#include <Arduino.h>
#include <Preferences.h>

Preferences prefs;

void setup() {
  Serial.begin(115200);
  Serial.println("PREFS_PROBE: start");
  prefs.begin("wifi", false);
  Serial.println("PREFS_PROBE: prefs.begin done");
  String s = prefs.getString("ssid", "");
  Serial.printf("PREFS_PROBE: ssid_len=%d\n", s.length());
}

void loop() {
  Serial.println("PREFS_PROBE: alive");
  delay(2000);
}