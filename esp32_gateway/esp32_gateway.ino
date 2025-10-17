// --- WiFi + Web ---
#include <WiFi.h>
#include <WebServer.h>
#include <Preferences.h>

// --- BLE (sensor y provisión WiFi para la APK) ---
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLEScan.h>
#include <BLEAdvertisedDevice.h>
#include <BLE2902.h>

// --- Bluetooth clásico (SPP) para provisión WiFi ---
#include <BluetoothSerial.h>

// --- FreeRTOS (ESP32 Arduino usa FreeRTOS) ---
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

// Prototipos de tareas FreeRTOS
void TaskButton(void* pv);
void TaskSPP(void* pv);
void TaskWeb(void* pv);
void TaskSensor(void* pv);
// Nueva tarea: escaneo de redes WiFi y notificación por BLE
void TaskWifiScan(void* pv);

// --- Servidor Web ---
WebServer server(80);
bool serverStarted = false;

// --- Persistencia de credenciales ---
Preferences prefs;
String wifiSSID = "";
String wifiPASS = "";
bool wifiReady = false;

// --- UUIDs del servicio BLE del sensor (lectura de humedad) ---
static BLEUUID sensorServiceUUID("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
static BLEUUID sensorCharUUID("beb5483e-36e1-4688-b7f5-ea07361b26a8");

// --- UUIDs del servicio BLE de provisión WiFi (APK) ---
static BLEUUID provServiceUUID("fefefefe-1234-5678-9abc-def012345678");
static BLEUUID ssidCharUUID("fefefefe-1234-5678-9abc-def012345679");
static BLEUUID passCharUUID("fefefefe-1234-5678-9abc-def01234567a");
static BLEUUID applyCharUUID("fefefefe-1234-5678-9abc-def01234567b");
static BLEUUID statusCharUUID("fefefefe-1234-5678-9abc-def01234567c");
static BLEUUID deviceIdCharUUID("fefefefe-1234-5678-9abc-def01234567d");
// Nuevos UUIDs para escaneo WiFi vía BLE
static BLEUUID wifiScanReqCharUUID("fefefefe-1234-5678-9abc-def01234567e");
static BLEUUID wifiScanResCharUUID("fefefefe-1234-5678-9abc-def01234567f");

// --- Bluetooth SPP ---
BluetoothSerial SerialBT;
String btBuffer = "";
bool sppEnabled = false;           // activo si SPP está iniciado
bool bleClientConnected = false;   // conexión activa al servicio de provisión
String gatewayId = "";            // ID único del gateway derivado de MAC

// Características BLE de provisión
BLECharacteristic* ssidChar = nullptr;
BLECharacteristic* passChar = nullptr;
BLECharacteristic* applyChar = nullptr;
BLECharacteristic* statusChar = nullptr;
BLECharacteristic* deviceIdChar = nullptr;
// Nuevas características para escaneo WiFi
BLECharacteristic* wifiScanReqChar = nullptr;
BLECharacteristic* wifiScanResChar = nullptr;
volatile bool wifiScanRequested = false;

// --- Estado del sensor BLE ---
static boolean sensorDoConnect = false;
static BLEAdvertisedDevice* sensorDevice = nullptr;
static float humidity = 0.0f;
bool sensorScanInitialized = false;
bool sensorScanInitPending = false;
// Botón para reset WiFi (GPIO0)
const int BTN_PIN = 0;
unsigned long btnPressStart = 0;
bool btnPressing = false;

// Callbacks BLE para escritura de SSID/PASS
class SSIDWriteCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    std::string v = c->getValue();
    wifiSSID = String(v.c_str());
    Serial.printf("SSID recibido (BLE): %s\n", wifiSSID.c_str());
    prefs.putString("ssid", wifiSSID);
  }
};

class PASSWriteCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) override {
    std::string v = c->getValue();
    wifiPASS = String(v.c_str());
    Serial.println("Password recibida (BLE).");
    prefs.putString("pass", wifiPASS);
  }
};

// Notificación de estado tanto por SPP como por BLE
void broadcastStatus(const char* s) {
  if (sppEnabled) {
    SerialBT.printf("STATUS:%s\n", s);
  }
  if (statusChar) {
    statusChar->setValue(s);
    statusChar->notify();
  }
}

bool connectWiFi(const String& ssid, const String& pass) {
  if (ssid.isEmpty()) return false;
  Serial.printf("Conectando a WiFi: %s...\n", ssid.c_str());
  broadcastStatus("connecting");
  WiFi.begin(ssid.c_str(), pass.c_str());
  for (int i = 0; i < 20; i++) { // ~10s
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("Conectado! IP: %s\n", WiFi.localIP().toString().c_str());
      prefs.putString("ssid", ssid);
      prefs.putString("pass", pass);
      broadcastStatus("success");
      wifiReady = true;
      // Detener advertising de provisión BLE y arrancar escaneo del sensor
      {
        BLEAdvertising* adv = BLEDevice::getAdvertising();
        adv->stop();
        Serial.println("Provisioning BLE desactivado (advertising detenido).");
        sensorScanInitPending = true;
      }
      // Reanudar SPP después de tener WiFi (si no está activo); se habilitará tras desconexión BLE
      return true;
    }
    delay(500);
  }
  Serial.println("Fallo en conexión WiFi.");
  broadcastStatus("fail");
  wifiReady = false;
  return false;
}

// --- Provisión por Bluetooth clásico (SPP) ---
void processBTLine(const String& line) {
  if (line.startsWith("SSID=")) {
    wifiSSID = line.substring(5);
    prefs.putString("ssid", wifiSSID);
    Serial.printf("SSID por BT: %s\n", wifiSSID.c_str());
    if (sppEnabled) SerialBT.println("OK SSID");
  } else if (line.startsWith("PASS=")) {
    wifiPASS = line.substring(5);
    prefs.putString("pass", wifiPASS);
    Serial.println("PASS por BT recibida");
    if (sppEnabled) SerialBT.println("OK PASS");
  } else if (line.equals("APPLY")) {
    bool ok = connectWiFi(wifiSSID, wifiPASS);
    if (ok && !serverStarted) {
      server.begin();
      serverStarted = true;
    }
  } else if (line.equals("STATUS")) {
    if (sppEnabled) SerialBT.println(wifiReady ? "STATUS:success" : "STATUS:awaiting");
  } else if (line.equals("IP")) {
    if (wifiReady && sppEnabled) SerialBT.printf("IP:%s\n", WiFi.localIP().toString().c_str());
  }
}

void handleBTProvision() {
  while (sppEnabled && SerialBT.available()) {
    char ch = (char)SerialBT.read();
    if (ch == '\r') continue;
    if (ch == '\n') {
      if (btBuffer.length() > 0) {
        processBTLine(btBuffer);
        btBuffer = "";
      }
    } else {
      btBuffer += ch;
    }
  }
}

// --- Escaneo del sensor BLE ---
class SensorScanCallbacks: public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) override {
    if (advertisedDevice.haveServiceUUID() && advertisedDevice.isAdvertisingService(sensorServiceUUID)) {
      BLEDevice::getScan()->stop();
      sensorDevice = new BLEAdvertisedDevice(advertisedDevice);
      sensorDoConnect = true;
    }
  }
};

void readSensorHumidity() {
  if (sensorDevice == nullptr) return;
  BLEClient* client = BLEDevice::createClient();
  if (!client->connect(sensorDevice)) return;
  BLERemoteService* srv = client->getService(sensorServiceUUID);
  if (!srv) { client->disconnect(); return; }
  BLERemoteCharacteristic* ch = srv->getCharacteristic(sensorCharUUID);
  if (!ch) { client->disconnect(); return; }
  if (ch->canRead()) {
    std::string v = ch->readValue();
    humidity = atof(v.c_str());
  }
  client->disconnect();
}

// --- Página web ---
void handleRoot() {
  String html = "<!DOCTYPE html><html><head><title>ESP32 Gateway</title><meta http-equiv=\"refresh\" content=\"5\"></head><body>";
  html += "<h1>Estado del Gateway</h1>";
  html += wifiReady ? (String("<p>WiFi: conectado (IP ") + WiFi.localIP().toString() + ")</p>") : String("<p>WiFi: no conectado</p>");
  html += "<h2>Sensor de Humedad</h2>";
  html += "<p>Humedad: " + String(humidity, 1) + "%</p>";
  html += "<p>Para configurar WiFi vía Bluetooth clásico (SPP): enviar 'SSID=...', 'PASS=...', 'APPLY'.</p>";
  html += "</body></html>";
  server.send(200, "text/html", html);
}

// Callbacks de servidor BLE para pausar/reanudar SPP
class ProvServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* /*pServer*/) override {
    bleClientConnected = true;
    // Al conectar BLE de provisión, pausar SPP para evitar conflicto
    if (sppEnabled) {
      Serial.println("SPP pausado por conexión BLE de provisión");
      SerialBT.end();
      sppEnabled = false;
    }
    // Informar estado a la APK
    broadcastStatus("awaiting");
  }
  void onDisconnect(BLEServer* /*pServer*/) override {
    bleClientConnected = false;
    // Reanudar SPP solo cuando ya tengamos WiFi (según lo solicitado)
    if (wifiReady && !sppEnabled) {
      SerialBT.begin("ESP32-Gateway");
      sppEnabled = true;
      Serial.println("SPP reanudado tras desconexión BLE y WiFi listo");
    }
  }
};

void setup() {
  Serial.begin(115200);
  // Botón reset WiFi
  pinMode(BTN_PIN, INPUT_PULLUP);
  Serial.println("Botón GPIO0 habilitado para reset WiFi (mantener 3s).");

  // Cargar credenciales almacenadas
  prefs.begin("wifi", false);
  wifiSSID = prefs.getString("ssid", "");
  wifiPASS = prefs.getString("pass", "");

  // ID único del gateway basado en MAC
  String macStr = WiFi.macAddress();
  macStr.replace(":", "");
  gatewayId = macStr.substring(macStr.length() - 6);
  Serial.printf("Gateway ID: %s\n", gatewayId.c_str());

  // Iniciar BLE primero (evita conflicto con SPP) y subir potencia
  BLEDevice::init((String("ESP32-Gateway-") + gatewayId).c_str());
  BLEDevice::setPower(ESP_PWR_LVL_P7);
  // Iniciar el servicio BLE de provisión para la APK
  startProvisioningBLE();
  
  // Intentar conectar si hay credenciales
  if (wifiSSID.length() > 0) {
    connectWiFi(wifiSSID, wifiPASS);
  }

  // SPP desactivado por defecto para priorizar descubrimiento BLE; se activará cuando haya WiFi
  if (wifiReady) {
    SerialBT.begin("ESP32-Gateway");
    sppEnabled = true;
    Serial.println("Bluetooth SPP listo (WiFi). Enviar: SSID=..., PASS=..., APPLY");
  } else {
    Serial.println("SPP desactivado hasta completar provisión BLE");
  }

  // Servidor web
  server.on("/", handleRoot);
  if (wifiReady && !serverStarted) {
    server.begin();
    serverStarted = true;
  }

  // Escaneo sensor BLE inicial solo si ya hay WiFi
  if (wifiReady) {
    BLEScan* scan = BLEDevice::getScan();
    scan->setAdvertisedDeviceCallbacks(new SensorScanCallbacks());
    scan->setActiveScan(true);
    scan->start(10, false);
    sensorScanInitialized = true;
  }

  // Crear tareas FreeRTOS
  xTaskCreatePinnedToCore(TaskButton, "btn", 2048, NULL, 2, NULL, 1);
  xTaskCreatePinnedToCore(TaskSPP, "spp", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(TaskWeb, "web", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(TaskSensor, "sensor", 8192, NULL, 1, NULL, 1);
  // Nueva tarea: escaneo WiFi y notificación por BLE
  xTaskCreatePinnedToCore(TaskWifiScan, "wifiscan", 6144, NULL, 1, NULL, 1);
}

void loop() {
  // Ceder CPU al scheduler, lógica corre en tareas
  vTaskDelay(100 / portTICK_PERIOD_MS);
}

// Servicio BLE de provisión (APK)
void startProvisioningBLE() {
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ProvServerCallbacks());
  BLEService* provService = pServer->createService(provServiceUUID);

  ssidChar = provService->createCharacteristic(ssidCharUUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  passChar = provService->createCharacteristic(passCharUUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ);
  applyChar = provService->createCharacteristic(applyCharUUID, BLECharacteristic::PROPERTY_WRITE);
  statusChar = provService->createCharacteristic(statusCharUUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  deviceIdChar = provService->createCharacteristic(deviceIdCharUUID, BLECharacteristic::PROPERTY_READ);
  // Nuevas características de escaneo WiFi
  wifiScanReqChar = provService->createCharacteristic(wifiScanReqCharUUID, BLECharacteristic::PROPERTY_WRITE);
  wifiScanResChar = provService->createCharacteristic(wifiScanResCharUUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);

  ssidChar->setCallbacks(new SSIDWriteCallbacks());
  passChar->setCallbacks(new PASSWriteCallbacks());
  class APPLYWriteCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* c) override {
      connectWiFi(wifiSSID, wifiPASS);
    }
  };
  applyChar->setCallbacks(new APPLYWriteCallbacks());

  // Callback para activar escaneo WiFi cuando la app escribe en la característica
  class ScanReqCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic* c) override {
      // cualquier valor escrito dispara escaneo
      wifiScanRequested = true;
      broadcastStatus("scanning_wifi");
    }
  };
  wifiScanReqChar->setCallbacks(new ScanReqCallbacks());

  statusChar->addDescriptor(new BLE2902());
  wifiScanResChar->addDescriptor(new BLE2902());
  statusChar->setValue("awaiting");
  deviceIdChar->setValue(gatewayId.c_str());

  provService->start();

  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(provServiceUUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("Provisioning BLE listo (servicio WiFi).");
}

// Resetea credenciales WiFi y reactiva provisión BLE
void resetWiFi() {
  Serial.println("Reseteo WiFi solicitado (GPIO0 3s).");
  WiFi.disconnect();
  wifiReady = false;
  prefs.remove("ssid");
  prefs.remove("pass");
  wifiSSID = "";
  wifiPASS = "";
  broadcastStatus("awaiting");

  // Pausar SPP si estaba activo
  if (sppEnabled) {
    SerialBT.end();
    sppEnabled = false;
    Serial.println("SPP pausado tras reset WiFi.");
  }

  // Detener escaneo del sensor y marcar flags
  BLEDevice::getScan()->stop();
  sensorScanInitialized = false;
  sensorScanInitPending = false;

  // Reactivar advertising del servicio de provisión BLE
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(provServiceUUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();
  Serial.println("Provisioning BLE reactivado para nueva configuración WiFi.");
}

// Tarea: lectura de botón para reset WiFi
void TaskButton(void* pv) {
  (void)pv;
  unsigned long start = 0;
  bool active = false;
  for (;;) {
    int val = digitalRead(BTN_PIN);
    if (val == LOW) {
      if (!active) { active = true; start = millis(); }
      if (active && (millis() - start >= 3000)) {
        resetWiFi();
        active = false;
        vTaskDelay(300 / portTICK_PERIOD_MS);
      }
    } else {
      active = false;
    }
    vTaskDelay(20 / portTICK_PERIOD_MS);
  }
}

// Tarea: provisión SPP concurrente
void TaskSPP(void* pv) {
  (void)pv;
  for (;;) {
    if (sppEnabled) {
      handleBTProvision();
    }
    vTaskDelay(10 / portTICK_PERIOD_MS);
  }
}

// Tarea: servidor web concurrente
void TaskWeb(void* pv) {
  (void)pv;
  for (;;) {
    if (wifiReady) {
      server.handleClient();
    }
    vTaskDelay(10 / portTICK_PERIOD_MS);
  }
}

// Tarea: escaneo y lectura del sensor BLE
void TaskSensor(void* pv) {
  (void)pv;
  for (;;) {
    if (wifiReady) {
      if (sensorScanInitPending && !sensorScanInitialized) {
        BLEScan* scan = BLEDevice::getScan();
        scan->setAdvertisedDeviceCallbacks(new SensorScanCallbacks());
        scan->setActiveScan(true);
        scan->start(10, false);
        sensorScanInitialized = true;
        sensorScanInitPending = false;
      }
      if (sensorDoConnect) {
        bool hadSPP = sppEnabled;
        if (hadSPP) { SerialBT.end(); sppEnabled = false; }
        readSensorHumidity();
        sensorDoConnect = false;
        if (wifiReady && !sppEnabled && hadSPP) {
          SerialBT.begin("ESP32-Gateway");
          sppEnabled = true;
        }
      }
      BLEDevice::getScan()->start(5, false);
    }
    vTaskDelay(1000 / portTICK_PERIOD_MS);
  }
}

// Nueva tarea: escaneo de redes WiFi y envío por BLE (una red por notificación)
void TaskWifiScan(void* pv) {
  (void)pv;
  for (;;) {
    if (wifiScanRequested && bleClientConnected) {
      wifiScanRequested = false;
      Serial.println("Escaneo WiFi solicitado por BLE...");
      // Ejecutar escaneo sincrónico
      int n = WiFi.scanNetworks();
      Serial.printf("WiFi: %d redes encontradas\n", n);
      if (wifiScanResChar) {
        for (int i = 0; i < n; i++) {
          String ssid = WiFi.SSID(i);
          int32_t rssi = WiFi.RSSI(i);
          int enc = WiFi.encryptionType(i);
          String line = ssid + "|" + String(rssi) + "|" + String(enc == WIFI_AUTH_OPEN ? 0 : 1);
          wifiScanResChar->setValue(line.c_str());
          wifiScanResChar->notify();
          vTaskDelay(30 / portTICK_PERIOD_MS);
        }
        wifiScanResChar->setValue("END");
        wifiScanResChar->notify();
      }
      WiFi.scanDelete();
      broadcastStatus("awaiting");
    }
    vTaskDelay(50 / portTICK_PERIOD_MS);
  }
}