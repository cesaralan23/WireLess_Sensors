#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEAdvertising.h>
#include <Preferences.h>
#include "esp_sleep.h"
#include "esp_system.h"
// OLED removido: sensor puro sin display
// Modo mantenimiento por botón (GPIO33)
#include "driver/rtc_io.h"
// Flag opcional de desarrollo para desactivar brownout (solo para pruebas)
// Habilitar definiendo DEV_NO_BROWNOUT antes de compilar
#ifdef DEV_NO_BROWNOUT
#include "soc/soc.h"
#include "soc/rtc_cntl_reg.h"
#endif

// Hardware mapping
// Swordprobe (soil moisture) input pin: use ADC1 to avoid conflicts with WiFi/BLE.
// GPIO32 is ADC1 and supports stable analog reads.
const int SWORDPROBE_PIN = 32; // swordprobe on GPIO32 (ADC1)
// Wake/maintenance button remains on GPIO33 (RTC IO) — configured elsewhere.

// Ciclo total deseado (segundos)
#define PERIOD_SECONDS 5       // ciclo total entre envíos (5s)
#define ADVERTISE_MS 1000      // tiempo de advertising en ms (1s)

const int WAKE_BUTTON_PIN = 33; // RTC IO, wake por nivel

// --- Calibración persistente y utilidades de lectura ---
Preferences prefs;
float SP_V_DRY = 2.8f; // valor por defecto si no calibrado
float SP_V_WET = 0.8f; // valor por defecto si no calibrado

static float readVoltageAvg(int samples = 8) {
  analogSetPinAttenuation(SWORDPROBE_PIN, ADC_11db);
  uint32_t mv_sum = 0;
  for (int i = 0; i < samples; ++i) {
    uint32_t mv = analogReadMilliVolts(SWORDPROBE_PIN);
    if (mv == 0) { // fallback si no disponible
      uint16_t raw = analogRead(SWORDPROBE_PIN);
      mv = (uint32_t)((raw / 4095.0f) * 3300.0f);
    }
    mv_sum += mv;
    delay(5);
  }
  return mv_sum / (float)samples / 1000.0f; // Voltios
}

static void loadCalibration() {
  prefs.begin("soil", false);
  float vd = prefs.getFloat("v_dry", NAN);
  float vw = prefs.getFloat("v_wet", NAN);
  if (!isnan(vd)) SP_V_DRY = vd;
  if (!isnan(vw)) SP_V_WET = vw;
  prefs.end();
}

static void saveCalibration(float vd, float vw) {
  prefs.begin("soil", false);
  prefs.putFloat("v_dry", vd);
  prefs.putFloat("v_wet", vw);
  prefs.end();
}

static void waitButtonRelease() {
  while (digitalRead(WAKE_BUTTON_PIN) == LOW) { delay(10); }
}

static void waitButtonPress(const char* prompt) {
  Serial.println(prompt);
  int last = digitalRead(WAKE_BUTTON_PIN);
  for (;;) {
    int cur = digitalRead(WAKE_BUTTON_PIN);
    if (cur == LOW && last == HIGH) break;
    last = cur;
    delay(10);
  }
  delay(50);
  waitButtonRelease();
}

static void calibrationWizard(uint16_t sensorId, BLEAdvertising* pAdvertising) {
  Serial.println("=== CALIBRACIÓN SWORDPROBE ===");
  Serial.println("Paso 1: Sonda al aire/seco. PRESIONA botón para capturar.");
  waitButtonPress("[Esperando botón para DRY]");
  float v_dry = readVoltageAvg(16);
  Serial.printf("Capturado DRY: %.3f V\n", v_dry);

  char buf1[48];
  snprintf(buf1, sizeof(buf1), "CAL_DRY=%.2f;ID=0x%04X", v_dry, sensorId);
  BLEAdvertisementData adv1; adv1.setFlags(0x04); adv1.setManufacturerData(std::string(buf1));
  pAdvertising->setAdvertisementData(adv1);
  pAdvertising->setScanResponse(false);
  pAdvertising->start();
  delay(1000);
  pAdvertising->stop();

  Serial.println("Paso 2: Sonda en suelo húmedo/agua. PRESIONA botón para capturar.");
  waitButtonPress("[Esperando botón para WET]");
  float v_wet = readVoltageAvg(16);
  Serial.printf("Capturado WET: %.3f V\n", v_wet);

  saveCalibration(v_dry, v_wet);
  SP_V_DRY = v_dry; SP_V_WET = v_wet;
  Serial.printf("Calibración guardada: DRY=%.2f V, WET=%.2f V\n", SP_V_DRY, SP_V_WET);

  char buf2[60];
  snprintf(buf2, sizeof(buf2), "CAL_OK;DRY=%.2f;WET=%.2f;ID=0x%04X", SP_V_DRY, SP_V_WET, sensorId);
  BLEAdvertisementData adv2; adv2.setFlags(0x04); adv2.setManufacturerData(std::string(buf2));
  pAdvertising->setAdvertisementData(adv2);
  pAdvertising->setScanResponse(false);
  pAdvertising->start();
  delay(1000);
  pAdvertising->stop();
}

static void autoCalibration(uint16_t sensorId, BLEAdvertising* pAdvertising, int waitSeconds = 10) {
  Serial.println("=== CALIBRACIÓN AUTOMÁTICA (2 puntos) ===");
  Serial.println("Tomando lectura DRY ahora. Luego mueve la sonda a agua/suelo húmedo.");
  float v_dry = readVoltageAvg(16);
  Serial.printf("DRY=%.3f V\n", v_dry);
  char buf1[48];
  snprintf(buf1, sizeof(buf1), "CAL_DRY=%.2f;ID=0x%04X", v_dry, sensorId);
  BLEAdvertisementData adv1; adv1.setFlags(0x04); adv1.setManufacturerData(std::string(buf1));
  pAdvertising->setAdvertisementData(adv1);
  pAdvertising->setScanResponse(false);
  pAdvertising->start();
  delay(1000);
  pAdvertising->stop();

  for (int s = waitSeconds; s > 0; --s) {
    char bufc[32]; snprintf(bufc, sizeof(bufc), "CAL_WAIT=%d;ID=0x%04X", s, sensorId);
    BLEAdvertisementData advc; advc.setFlags(0x04); advc.setManufacturerData(std::string(bufc));
    pAdvertising->setAdvertisementData(advc);
    pAdvertising->setScanResponse(false);
    pAdvertising->start();
    delay(1000);
    pAdvertising->stop();
  }

  float v_wet = readVoltageAvg(16);
  Serial.printf("WET=%.3f V\n", v_wet);
  saveCalibration(v_dry, v_wet);
  SP_V_DRY = v_dry; SP_V_WET = v_wet;
  Serial.printf("Calibración auto guardada: DRY=%.2f V, WET=%.2f V\n", SP_V_DRY, SP_V_WET);

  char buf2[60];
  snprintf(buf2, sizeof(buf2), "CAL_OK;DRY=%.2f;WET=%.2f;ID=0x%04X", SP_V_DRY, SP_V_WET, sensorId);
  BLEAdvertisementData adv2; adv2.setFlags(0x04); adv2.setManufacturerData(std::string(buf2));
  pAdvertising->setAdvertisementData(adv2);
  pAdvertising->setScanResponse(false);
  pAdvertising->start();
  delay(1000);
  pAdvertising->stop();
}

void setup() {
  Serial.begin(115200);
  delay(100);
#ifdef DEV_NO_BROWNOUT
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);
  Serial.println("[DEV] Brownout detector desactivado");
#endif
  Serial.println("Sensor Soil (swordprobe) booting... (advertise -> sleep)");
  pinMode(WAKE_BUTTON_PIN, INPUT_PULLUP);
  // Asegurar pull-up en dominio RTC para ext0 durante deep sleep
  rtc_gpio_pullup_en((gpio_num_t)WAKE_BUTTON_PIN);
  rtc_gpio_pulldown_dis((gpio_num_t)WAKE_BUTTON_PIN);

  // Log pin mapping for maintenance
  Serial.printf("Pin mapping: swordprobe on GPIO%d (ADC1), wake button on GPIO33 (RTC)\n", SWORDPROBE_PIN);

  // Cargar calibración existente
  loadCalibration();
  Serial.printf("Calibración actual: DRY=%.2f V, WET=%.2f V\n", SP_V_DRY, SP_V_WET);
  // No HTU21D: este firmware es solo para humedad de suelo mediante swordprobe

  // Leer swordprobe en GPIO32 (ADC1) y loguear valor promedio
  pinMode(SWORDPROBE_PIN, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(SWORDPROBE_PIN, ADC_11db); // cubrir ~0-3.3V
  float sp_v = readVoltageAvg(8);
  Serial.printf("Swordprobe GPIO%d ~%.3f V (avg)\n", SWORDPROBE_PIN, sp_v);

  // Estimar porcentaje de humedad del suelo (0–100%) a partir de voltaje
  // Usar calibración guardada (o valores por defecto)
  float span = SP_V_DRY - SP_V_WET;
  if (span < 0.05f) span = 0.05f; // evitar división muy pequeña
  float norm = (SP_V_DRY - sp_v) / span; // seco->0, húmedo->1
  if (norm < 0) norm = 0; if (norm > 1) norm = 1;
  float soilPct = norm * 100.0f;
  Serial.printf("Soil moisture estimate: %.1f%% (dry=%.1fV wet=%.1fV)\n", soilPct, SP_V_DRY, SP_V_WET);

  // Derivar sensorId desde la MAC (últimos 2 bytes)
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  uint16_t sensorId = (uint16_t)((mac[4] << 8) | mac[5]);

  // Detectar causa de wake para elegir modo
  esp_sleep_wakeup_cause_t wakeCause = esp_sleep_get_wakeup_cause();

  // Sin Service Data: se anunciará solo ManufacturerData con SM=xx.x e ID

  // Inicializar BLE (común)
  BLEDevice::init("ESP32-Sensor-Soil");
  // Bajar potencia de TX BLE para evitar picos de consumo que disparen brownout
  BLEDevice::setPower(ESP_PWR_LVL_N0);
  // Pequeña estabilización antes de empezar advertising
  delay(250);
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  // Función lambda para anunciar con ManufacturerData + ServiceData
  auto advertise_once = [&](const char* manufacturer) {
    BLEAdvertisementData advData;
    advData.setFlags(0x04);
    if (manufacturer) {
      advData.setManufacturerData(std::string(manufacturer));
      Serial.printf("ManufacturerData: %s\n", manufacturer);
    }
    pAdvertising->setAdvertisementData(advData);
    pAdvertising->setScanResponse(false);
    pAdvertising->start();
  };

  if (wakeCause == ESP_SLEEP_WAKEUP_EXT0 || wakeCause == ESP_SLEEP_WAKEUP_EXT1) {
    // Wake por botón: si el botón ya fue soltado, ejecutar calibración automática.
    // Si sigue presionado, mantener modo mantenimiento clásico.
    if (digitalRead(WAKE_BUTTON_PIN) == HIGH) {
      Serial.println("Wake by button: auto-calibration 2-point");
      autoCalibration(sensorId, pAdvertising, 10);
      // Deep sleep post calibración
      uint64_t period_us = (uint64_t)PERIOD_SECONDS * 1000000ULL;
      esp_sleep_enable_timer_wakeup(period_us);
      esp_sleep_enable_ext0_wakeup(GPIO_NUM_33, 0);
      Serial.println("Auto calibration done: deep sleeping");
      delay(10);
      esp_deep_sleep_start();
    } else {
      // Modo mantenimiento por botón: alive 15s con avisos en 15/10/5
      Serial.println("Wake by button: maintenance window 15s");
      char buf[48];
      snprintf(buf, sizeof(buf), "BTN_WAKE;ALIVE=15;ID=0x%04X", sensorId);
      advertise_once(buf);
      delay(5000);
      pAdvertising->stop();
      snprintf(buf, sizeof(buf), "BTN_WAKE;ALIVE=10;ID=0x%04X", sensorId);
      advertise_once(buf);
      delay(5000);
      pAdvertising->stop();
      snprintf(buf, sizeof(buf), "BTN_WAKE;ALIVE=5;ID=0x%04X", sensorId);
      advertise_once(buf);
      delay(5000);
      pAdvertising->stop();

      uint64_t period_us = (uint64_t)PERIOD_SECONDS * 1000000ULL;
      esp_sleep_enable_timer_wakeup(period_us);
      esp_sleep_enable_ext0_wakeup(GPIO_NUM_33, 0);
      Serial.println("Maintenance done: deep sleeping");
      delay(10);
      esp_deep_sleep_start();
    }
  } else {
    // Si el botón está presionado al arrancar por >3s, entrar en asistente de calibración
    unsigned long t0 = millis();
    bool held = false;
    while (millis() - t0 < 3000) {
      if (digitalRead(WAKE_BUTTON_PIN) == LOW) held = true; else { held = false; break; }
      delay(10);
    }
    if (held) {
      calibrationWizard(sensorId, pAdvertising);
      // Recalcular tras calibración
      sp_v = readVoltageAvg(8);
      span = SP_V_DRY - SP_V_WET;
      if (span < 0.05f) span = 0.05f;
      norm = (SP_V_DRY - sp_v) / span;
      if (norm < 0) norm = 0; if (norm > 1) norm = 1;
      soilPct = norm * 100.0f;
    }
    // Modo normal: advertise 1s y dormir el resto del período
    char shout_buf[32];
    snprintf(shout_buf, sizeof(shout_buf), "SM=%.1f;ID=0x%04X", soilPct, sensorId);
    Serial.printf("Advertising soil moisture (ManufacturerData) sensorId=0x%04X SM=%.1f%%\n", sensorId, soilPct);
    advertise_once(shout_buf);
    delay(ADVERTISE_MS);
    pAdvertising->stop();

    uint64_t period_us = (uint64_t)PERIOD_SECONDS * 1000000ULL;
    uint64_t adv_us = (uint64_t)ADVERTISE_MS * 1000ULL;
    uint64_t sleep_us = 0;
    if (period_us > adv_us) sleep_us = period_us - adv_us;
    else sleep_us = 0; // fallback

    if (sleep_us == 0) {
      Serial.println("Advertise >= period: sleeping 1s as fallback");
      esp_sleep_enable_timer_wakeup(1000000ULL);
    } else {
      Serial.printf("Going to deep sleep for %llu us (~%llu s)\n", sleep_us, sleep_us / 1000000ULL);
      esp_sleep_enable_timer_wakeup(sleep_us);
    }
    // Habilitar wake por botón también en modo normal
    esp_sleep_enable_ext0_wakeup(GPIO_NUM_33, 0);
    delay(10);
    esp_deep_sleep_start();
  }
}

void loop() {
  // No se llega aquí porque se hace deep sleep en setup
}