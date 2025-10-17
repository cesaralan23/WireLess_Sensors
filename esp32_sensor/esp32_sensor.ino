#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// Definiciones para el servicio y característica BLE
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLECharacteristic *pCharacteristic;
bool deviceConnected = false;

// Simulación de un valor de humedad
float humidity = 45.5;

// Callbacks para la conexión y desconexión de dispositivos
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Iniciando ESP32 como Sensor BLE...");

  // Crear el dispositivo BLE
  BLEDevice::init("ESP32 Sensor de Humedad");

  // Crear el servidor BLE
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Crear el servicio BLE
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Crear una característica BLE
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Añadir un descriptor
  pCharacteristic->addDescriptor(new BLE2902());

  // Iniciar el servicio
  pService->start();

  // Iniciar el advertising (anuncio)
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // Ayuda a la conexión en iOS
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("Sensor listo para recibir conexiones.");
}

void loop() {
    if (deviceConnected) {
        // Simular un cambio en la humedad
        humidity += 0.1;
        if (humidity > 100) {
            humidity = 0;
        }

        // Actualizar el valor de la característica
        pCharacteristic->setValue(humidity);
        pCharacteristic->notify(); // Notificar a los clientes suscritos
        Serial.print("Nuevo valor de humedad enviado: ");
        Serial.println(humidity);
    }

    // Desconectar para ahorrar energía si no hay nadie conectado
    // y volver a anunciar para que otros lo encuentren.
    if (!deviceConnected) {
        delay(500); // Un pequeño delay para no saturar
        BLEDevice::startAdvertising();
    }
    
    delay(2000);
}