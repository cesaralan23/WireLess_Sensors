// blink_only/blink_only.ino - prueba con Serial para verificar arranque y ejecucion
const int LED_PIN = 2;

void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("minimal_test: setup start");
  pinMode(LED_PIN, OUTPUT);
  Serial.println("minimal_test: setup done");
}

void loop() {
  digitalWrite(LED_PIN, HIGH);
  Serial.println("LED ON");
  delay(500);
  digitalWrite(LED_PIN, LOW);
  Serial.println("LED OFF");
  delay(500);
}