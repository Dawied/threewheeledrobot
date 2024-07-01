// revisions:
// 19-06-2024 motor ENC1 not used anymore

/// todo:
// setWheelSpeeds doen in moveRobot en rotateRobot ipv loop
// ws1 - ws3 parameters maken in setWheelSpeed en globals 
// verwijderen


#include <Arduino.h>
#include <Math.h>
#include <soc/efuse_reg.h>
#include <Streaming.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <BLEUUID.h>
#include <MPU6050_6Axis_MotionApps20.h>
#include <I2Cdev.h>
#if I2CDEV_IMPLEMENTATION == I2CDEV_ARDUINO_WIRE
#include "Wire.h"
#endif
#include <MotorControl.h>

bool debug = true;

std::map<String, float> dynVars;

int motorCount = 3;

//
// Begin blue tooth 
//
BLEServer* pServer = NULL;
BLECharacteristic* pSensorCharacteristic = NULL;
BLECharacteristic* pCmdCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
const int onBoardLed = 2;

// https://www.uuidgenerator.net/

#define SERVICE_UUID        "972830ca-08b4-4c05-8a09-786f366e4e7a"
#define SENSOR_CHARACTERISTIC_UUID "62bebe3e-33a2-4ad8-90cb-ed91ad1d779f"
#define CMD_CHARACTERISTIC_UUID "28d4c6aa-1559-4788-aaf7-a61b098318da"

const int MOTOR_CMD = 1;
const int MOVE_CMD = 2;
const int ROTATE_CMD = 3;
const int STOP_CMD = 4;
const int CALIBRATE_CMD = 10;
const int DYNVAR_CMD = 20;
const int LED_CMD = 30;

//
// End blue tooth
//

//
// Begin motor vars
//

const int DRIVE_TYPE_STOP = 0;
const int DRIVE_TYPE_SINGLE = 1;
const int DRIVE_TYPE_MOVE = 2;
const int DRIVE_TYPE_ROTATE = 3;
const int DRIVE_TYPE_ROTATEMOVE = 4;

int driveType = DRIVE_TYPE_STOP;

const int MOVE_TYPE_FIXED = 0;
const int MOVE_TYPE_ANGLED = 1;
int moveType = MOVE_TYPE_FIXED;

//const int CW = 1;
//const int CCW = 2;

MotorControl motors[] = {
  MotorControl(
    33,    // pin input 1    
    25,    // pin input 2    
    26,    // pin PWM control
    34,    // pin encoder C2
    1,     // PWM Channel
    debug
  ),
  MotorControl(
    0,     // pin input 1    
    2,     // pin input 2    
    15,    // pin PWM control
    17,    // pin encoder C2
    2,     // PWM Channel
    debug
  ),
  MotorControl(
    27,    // pin input 1    
    14,    // pin input 2    
    12,    // pin PWM control
    35,    // pin encoder C2
    3,     // PWM Channel
    debug
  )
};

const uint16_t STBY = 13;          // Motor STBY control, one pin to rule them all

int ANALOG_WRITE_BITS = 8;
int freq = 100000;
const uint16_t MAX_PWM = pow(2, ANALOG_WRITE_BITS) - 1;
// minimum PWM value
const uint16_t MIN_PWM = MAX_PWM / 5;

//
// End motor vars
//

// Wheel characteritics
const float wheelRadius = 0.03; // Distance from center to wheel (in meters)

// Motor globals
float desiredAngleDeg = 0.0;
int desiredSpeedMs = 0;
float ws1 = 0, ws2 = 0, ws3 = 0;

// PID
double pidKp = 0.6, pidKi = 0.9, pidKd = 0.0;

int loopInterval = 20;

// Serial input
char cmd;
int selectedMotor = 1;

// MPU 6050
const int mpuInterruptPin = 32;
const int MPU = 0x68;
MPU6050 mpu;

uint16_t fifoCount;
uint8_t fifoBuffer[64];
Quaternion q;

volatile bool mpuInterrupt = false;
uint8_t mpuDevStatus;
uint16_t mpuFIFOPacketSize;
bool dmpReady = false;

VectorFloat gravity;
float ypr[3]; // yaw, pitch, roll
float curYaw = 0.0; // the yaw in radians
float prevYaw = 0.0; // previous curYaw for reporting
float cartesianYaw = 0.0;  // the yaw in cartesian degrees

bool yawChangeNotified = true;

// function declarations
void adjustPID(String varName);
void setupDynVars();
void setupMotors();
void setupBlueTooth();
void setupMPU6050();
void processMPU6050();
void serialMotorInput();
void processBlueTooth();
void moveRobot(float targetAngle, float speed, bool turnToTargetAngle, float& ws1, float& ws2, float& ws3);
void rotateRobot(float targetAngle, float speed, float& ws1, float& ws2, float& ws3);
int calculateRotateDirection(float targetAngle);
float calculateRotateSpeed(float targetAngle, float speed);
void setWheelSpeeds();
void stopMotors();
void IRAM_ATTR onMPUInterrupt();
void IRAM_ATTR onMotor1Pulse();
void IRAM_ATTR onMotor2Pulse();
void IRAM_ATTR onMotor3Pulse();

// BLE
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
  };

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
  }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {

    int motor;
    int speed;
    int direction;
    int speedType;
    int ledValue;
    int moveDirection;
    int moveSpeed;
    int turnToAngle;

    BLEUUID uuid = pCharacteristic->getUUID();
    std::string value = pCharacteristic->getValue();

    int cmd = static_cast<int>(value[0]);

    char dynVarName[3];
    float dynVarValue = 0.0;

    switch (cmd)
    {
      // Drive an individual motor with speed and direction (cw, ccw)
      case MOTOR_CMD:
        motor = static_cast<int>(value[1]);
        speed = static_cast<int>(value[2]);
        direction = static_cast<int>(value[3]);  // 1 = cw, 2 = ccw
        speedType = (static_cast<int>(value[4] == SPEED_TYPE_PWM)) ? SPEED_TYPE_PWM : SPEED_TYPE_RPM;
        driveType = DRIVE_TYPE_SINGLE;

        if (debug) Serial << "MOTOR_CMD"
          << " motor: " << motor
          << " speed: " << speed
          << " direction: " << (direction == 1 ? "cw" : "ccw")
          << " speedType: " << (speedType == SPEED_TYPE_PWM ? "PWM" : "RPM")
          << endl;

        motors[motor - 1].setSpeed(speed, speedType, direction);
        break;
      case MOVE_CMD:
        moveDirection = (uint8_t)value[1] | ((uint8_t)value[2] << 8);
        moveSpeed = (uint8_t)value[3] | ((uint8_t)value[4] << 8); //static_cast<int>(value[3]);
        turnToAngle = static_cast<int>(value[5]);
        driveType = DRIVE_TYPE_MOVE;
        moveType = turnToAngle == 1 ? MOVE_TYPE_ANGLED : MOVE_TYPE_FIXED;
        desiredAngleDeg = (moveDirection + 360) % 360;
        desiredSpeedMs = moveSpeed;

        if (debug) Serial << "MOVE_CMD "
          << "direction: " << moveDirection
          << " turnToAngle: " << turnToAngle
          << " speed: " << moveSpeed << endl;
        break;
      case ROTATE_CMD:
        moveDirection = (uint8_t)value[1] | ((uint8_t)value[2] << 8);
        moveSpeed = (uint8_t)value[3] | ((uint8_t)value[4] << 8);
        driveType = DRIVE_TYPE_ROTATE;
        desiredAngleDeg = (moveDirection + 360) % 360;
        desiredSpeedMs = moveSpeed;

        if (debug) Serial << "ROTATE_CMD " << "direction: " << moveDirection << " speed: " << moveSpeed << endl;
        break;
      case STOP_CMD:
        driveType = DRIVE_TYPE_STOP;
        desiredAngleDeg = cartesianYaw;
        desiredSpeedMs = 0.0;
        if (debug) Serial << "STOP_CMD" << endl;
        break;
      case CALIBRATE_CMD:
        setupMPU6050();
        prevYaw = 0;
        curYaw = 0;
        cartesianYaw = 0;
        if (debug) Serial << "CALIBRATE_CMD" << endl;
        break;
      case DYNVAR_CMD:
        dynVarName[0] = (char)value[4];
        dynVarName[1] = (char)value[5];
        dynVarName[2] = '\0'; // Null-terminate the string      
        dynVarValue = *((float*)&value[6]);

        dynVars[dynVarName] = dynVarValue;
        adjustPID(dynVarName);

        if (debug) Serial << "DYNVAR_CMD " << "name: " << dynVarName << " value: " << dynVarValue << endl;
        break;
      case LED_CMD:
        ledValue = static_cast<int>(value[1]);
        if (debug) Serial << "LED_CMD " << "value: " << ledValue << endl;
        digitalWrite(onBoardLed, ledValue);
        break;
    }
  }
};

void setup() {
  if (debug)
  {
    Serial.begin(115200);
    while (!Serial);
    Serial << "Started" << endl << endl;
  }

  setupDynVars();
  setupMPU6050();
  setupBlueTooth();
  setupMotors();
}

void loop()
{
  //serialMotorInput();
  processBlueTooth();
  processMPU6050();

  bool turnToTargetAngle;
  switch (driveType)
  {
    case DRIVE_TYPE_MOVE:
      turnToTargetAngle = moveType == MOVE_TYPE_ANGLED;
      moveRobot(desiredAngleDeg, desiredSpeedMs, turnToTargetAngle, ws1, ws2, ws3);
      setWheelSpeeds();
      break;
    case DRIVE_TYPE_ROTATE:
      rotateRobot(desiredAngleDeg, desiredSpeedMs, ws1, ws2, ws3);
      setWheelSpeeds();
      break;
    case DRIVE_TYPE_STOP:
      stopMotors();
      break;
  }

  // Drive the motors
  for (int i = 0; i < motorCount; i++)
  {
    motors[i].setPID();
    motors[i].drive();
  }
  delay(loopInterval);
}

/***
 * Calculate the wheel velocities of a three wheeled omnidirectional robot based on the robot angle, the robot speed an the robot orientation
 *
 * targetAngle is in cartesian degrees
 * curYaw is in radians
 *
 * Assumed positions of the wheels:
 * Wheel 1 (ws1): Positioned at an angle of 180 degrees, at the back
 * Wheel 2 (ws2): Positioned at an angle of 300 degrees, left front
 * Wheel 3 (ws3): Positioned at an angle of 60 degrees, right front
 *
 * This will move the robot in the direction of 'angle' relative to the position of wheel 1
*/
void moveRobot(float targetAngle, float speed, bool turnToTargetAngle, float& ws1, float& ws2, float& ws3) {
  // Convert angle to radians
  float moveAngleRad = radians(targetAngle);

  // Calculate the vector components of the desired movement angle
  float Vx = speed * cos(moveAngleRad);
  float Vy = speed * sin(moveAngleRad);

  // Adjust velocity for current robot orientation
  float Vx_prime = Vx * cos(curYaw) - Vy * sin(curYaw);
  float Vy_prime = Vx * sin(curYaw) + Vy * cos(curYaw);

  float rotateSpeed = 0;

  // Calculate the rotational speed to rotate to targetAngle while moving
  if (turnToTargetAngle)
  {
    int direction = calculateRotateDirection(targetAngle);
    rotateSpeed = calculateRotateSpeed(targetAngle, speed) * direction;
    Serial << "rotateSpeed: " << rotateSpeed << endl;
  }

  // Calculate wheel velocities
  // 0.5 = cos(120)
  // sqrt(3)/2 = sin(120)
  ws1 = Vx_prime;
  ws2 = (-0.5 * Vx_prime - (sqrt(3) / 2) * Vy_prime);
  ws3 = (-0.5 * Vx_prime + (sqrt(3) / 2) * Vy_prime);

  // add rotational speed needed to turn north side to targetAngle
  ws1 += rotateSpeed;
  ws2 += rotateSpeed;
  ws3 += rotateSpeed;

  if (debug) Serial
    << "targetAngle: " << targetAngle
    << " speed: " << speed
    << " ws1: " << ws1
    << " ws2: " << ws2
    << " ws3: " << ws3 << endl;
}

/**
 * @brief rotate to targetAngle
 *
 * @param targetAngle in cartesian degrees
 * @param ws1
 * @param ws2
 * @param ws3
 */
void rotateRobot(float targetAngle, float speed, float& ws1, float& ws2, float& ws3)
{
  int direction = calculateRotateDirection(targetAngle);

  float rotateSpeed = calculateRotateSpeed(targetAngle, speed) * direction;

  if (rotateSpeed == 0)
  {
    driveType = DRIVE_TYPE_STOP;
  }

  ws1 = ws2 = ws3 = rotateSpeed;

  if (debug) Serial
    << "targetAngle: " << targetAngle
    << " cartesianYaw: " << cartesianYaw
    << " speed: " << speed
    << " wheelSpeed: " << rotateSpeed
    << endl;
}

float calculateRotateSpeed(float targetAngle, float speed) 
{
  // Slow down within 10 degrees of the target
  float speedFactor = 1.0;
  float rotateSpeed = 0;

  if (abs(targetAngle - cartesianYaw) < 10)
  {
    speedFactor = abs(targetAngle - cartesianYaw) / 360;
  }

  if (abs(targetAngle - cartesianYaw) > 1)
  {
    rotateSpeed = min(max(speed * speedFactor, (float)10), (float)200);
  }

  return rotateSpeed;
}

/**
 * @brief Calculate rotation direction for the shortest path to targetAngle
 *        base on the current angle
 *
 * @param targetAngle
 * @return float
 */
int calculateRotateDirection(float targetAngle)
{
  // determine the shortest distance to targetAngle
  float cwDistance = fmod(cartesianYaw - targetAngle, 360);
  float ccwDistance = fmod(targetAngle - cartesianYaw, 360);
  int direction;
  if ((targetAngle < cartesianYaw && (cartesianYaw - targetAngle) <= 180) || (targetAngle > cartesianYaw && (targetAngle - cartesianYaw) > 180))
  {
    direction = -1;
  }
  else
  {
    direction = 1;
  }

  return direction;
}

/**
 * @brief set the targetRPM and direction (cw, ccw) of the wheels
 *
 *
 * @param angle desired angle in degrees
 * @param speed
 */
void setWheelSpeeds()
{
  // Set the motor speeds
  motors[0].speedType = SPEED_TYPE_RPM;
  motors[0].direction = ws1 > 0 ? CW : CCW;
  motors[0].targetRPM = abs(ws1);

  motors[1].speedType = SPEED_TYPE_RPM;
  motors[1].direction = ws2 > 0 ? CW : CCW;
  motors[1].targetRPM = abs(ws2);

  motors[2].speedType = SPEED_TYPE_RPM;
  motors[2].direction = ws3 > 0 ? CW : CCW;
  motors[2].targetRPM = abs(ws3);
}

void stopMotors()
{
  for (int i = 0; i < motorCount; i++)
  {
    motors[i].stop();
  }
  ws1 = ws2 = ws3 = 0;
}

void processBlueTooth()
{
  // notify changed value of cartesianYaw
  // wordt (nog) niet gebruikt, uitgezet

  /*
  if (deviceConnected && !yawChangeNotified) {
    char buffer[20];
    pSensorCharacteristic->setValue(String(cartesianYaw).c_str());
    pSensorCharacteristic->notify();

    yawChangeNotified = true;

    if (debug) Serial << "yaw change notified: " << String(cartesianYaw).c_str() << endl;
  }
  */

  // disconnecting
  if (!deviceConnected && oldDeviceConnected) {
    if (debug) Serial << "Device disconnected." << endl;
    delay(500); // give the bluetooth stack the chance to get things ready
    pServer->startAdvertising(); // restart advertising
    if (debug) Serial << "Start advertising" << endl;
    oldDeviceConnected = deviceConnected;
  }
  // connecting
  if (deviceConnected && !oldDeviceConnected) {
    // do stuff here on connecting
    oldDeviceConnected = deviceConnected;
    if (debug) Serial << "Device Connected" << endl;
  }
}

void processMPU6050()
{
  if (!dmpReady) return;

  if (mpu.dmpGetCurrentFIFOPacket(fifoBuffer)) 
  {
      mpu.dmpGetQuaternion(&q, fifoBuffer);
      mpu.dmpGetGravity(&gravity, &q);
      mpu.dmpGetYawPitchRoll(ypr, &q, &gravity);

      // Extract the yaw angle (robot's orientation in radians)
      curYaw = ypr[0];

      // Convert to cartesian degrees
      cartesianYaw = fmod(450 - curYaw * 180 / M_PI, 360);

      if (abs(prevYaw - curYaw) > radians(0.5))
      {
        prevYaw = curYaw;
        yawChangeNotified = false;
        if (debug) Serial
          << "curYaw: " << curYaw
          << " cartesian: " << cartesianYaw
          //<< " millis: " << millis()
          << endl;
      }
  }
}

void setupMotors()
{
  for (int i = 0; i < motorCount; i++)
  {
    // init motor input pins
    pinMode(motors[i].IN1, OUTPUT);
    pinMode(motors[i].IN2, OUTPUT);

    pinMode(motors[i].ENC2, INPUT); // motor has internal pull-up resistor on encoder

    // attach sensor interrupts
    if (i == 0) attachInterrupt(digitalPinToInterrupt(motors[0].ENC2), onMotor1Pulse, RISING);
    if (i == 1) attachInterrupt(digitalPinToInterrupt(motors[1].ENC2), onMotor2Pulse, RISING);
    if (i == 2) attachInterrupt(digitalPinToInterrupt(motors[2].ENC2), onMotor3Pulse, RISING);

    // Setting the channel, frequency, and accuracy of the ESP32 pin used for PWM outputs
    ledcSetup(motors[i].pwmChannel, freq, ANALOG_WRITE_BITS);
    ledcAttachPin(motors[i].PWM, motors[i].pwmChannel);

    // Set pid tunings
    motors[i].setPIDTunings(pidKp, pidKi, pidKd);
  }

  pinMode(STBY, OUTPUT);

  // Set standby for all motors to HIGH
  digitalWrite(STBY, HIGH);
}

void setupMPU6050()
{
#if I2CDEV_IMPLEMENTATION == I2CDEV_ARDUINO_WIRE
  Wire.begin();
  Wire.setClock(400000); // 400kHz I2C clock. Comment this line if having compilation difficulties
#elif I2CDEV_IMPLEMENTATION == I2CDEV_BUILTIN_FASTWIRE
  Fastwire::setup(400, true);
#endif  
  mpu.initialize();

  pinMode(mpuInterruptPin, INPUT);

  mpuDevStatus = mpu.dmpInitialize();

  if (mpuDevStatus == 0) {
    Serial << "Calibrating MPU..." << endl;

    // last calibrated values 25-6-2024 (from IMU_ZERO)
    mpu.setXAccelOffset(-406);
    mpu.setYAccelOffset(-348);
    mpu.setZAccelOffset(1027);
    mpu.setXGyroOffset(64);
    mpu.setYGyroOffset(-20);
    mpu.setZGyroOffset(38);

    mpu.CalibrateAccel(12);
    mpu.CalibrateGyro(12);
    Serial << endl;

    mpu.setDMPEnabled(true);
    attachInterrupt(digitalPinToInterrupt(mpuInterruptPin), onMPUInterrupt, RISING);
    mpu.getIntStatus();
    mpuFIFOPacketSize = mpu.dmpGetFIFOPacketSize();
    dmpReady = true;
  }
  else
  {
    // ERROR!
    // 1 = initial memory load failed
    // 2 = DMP configuration updates failed
    // (if it's going to break, usually the code will be 1)
    Serial << "DMP Initialization failed " << mpuDevStatus << endl;
  }

  //if (debug) Serial << (mpu.testConnection() ? "IMU initialized correctly" : "Error initializing IMU") << endl;
}

void setupBlueTooth()
{
  pinMode(onBoardLed, OUTPUT);

  // Create the BLE Device
  BLEDevice::init("TWR1");

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // Create the BLE Sensor Characteristic
  pSensorCharacteristic = pService->createCharacteristic(
    SENSOR_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_NOTIFY |
    BLECharacteristic::PROPERTY_INDICATE
  );

  // Create the BLE Cmd Characteristic
  pCmdCharacteristic = pService->createCharacteristic(
    CMD_CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );

  // Register the callback for the cmd characteristic
  pCmdCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  // https://www.bluetooth.com/specifications/gatt/viewer?attributeXmlFile=org.bluetooth.descriptor.gatt.client_characteristic_configuration.xml
  // Create a BLE Descriptor
  pSensorCharacteristic->addDescriptor(new BLE2902());
  pCmdCharacteristic->addDescriptor(new BLE2902());

  // Start the service
  pService->start();

  // Start advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(false);
  pAdvertising->setMinPreferred(0x0);  // set value to 0x00 to not advertise this parameter
  BLEDevice::startAdvertising();
  if (debug) Serial << "Waiting a client connection to notify..." << endl;
}

void IRAM_ATTR onMPUInterrupt()
{
  mpuInterrupt = true;
}

void IRAM_ATTR onMotor1Pulse()
{
  motors[0].pulseCount++;
}
void IRAM_ATTR onMotor2Pulse()
{
  motors[1].pulseCount++;
}
void IRAM_ATTR onMotor3Pulse()
{
  motors[2].pulseCount++;
}

void serialMotorInput()
{
  cmd = Serial.read();

  // change motor
  if (cmd == '1') { selectedMotor = 1; if (debug) Serial << "Select motor 1" << endl; }
  if (cmd == '2') { selectedMotor = 2; if (debug) Serial << "Select motor 2" << endl; }
  if (cmd == '3') { selectedMotor = 3; if (debug) Serial << "Select motor 3" << endl; }

  int i = selectedMotor - 1;

  // CW
  if (cmd == '4')
  {
    // reset speed
    if (motors[i].direction == CCW || motors[i].targetPWM == 0)
    {
      motors[i].targetPWM = MIN_PWM;
    }
    else
    {
      motors[i].targetPWM += 10;
    }
    motors[i].direction = CW;

    motors[i].speedType = SPEED_TYPE_PWM;
    motors[i].drive();

    if (debug) Serial << "Forward " << motors[i].targetPWM << endl;
  }

  // CCW
  if (cmd == '5')
  {
    // reset speed
    if (motors[i].direction == CW || motors[i].targetPWM == 0)
    {
      motors[i].targetPWM = MIN_PWM;
    }
    else
    {
      motors[i].targetPWM += 10;
    }
    motors[i].direction = CCW;

    motors[i].speedType = SPEED_TYPE_PWM;
    motors[i].drive();

    if (debug) Serial << "Backward " << motors[i].targetPWM << endl;
  }

  // stop
  if (cmd == '6')
  {
    motors[i].targetPWM = 0;
    motors[i].speedType = SPEED_TYPE_PWM;
    motors[i].drive();

    if (debug) Serial << "Stop " << endl;
  }
}

void setupDynVars()
{
  dynVars["kp"] = 0;
  dynVars["ki"] = 0;
  dynVars["kd"] = 0;
}

void adjustPID(String varName)
{
  if (varName == "kp") {
    pidKp = dynVars["kp"];
    driveType = DRIVE_TYPE_STOP;
    stopMotors();
    motors[0].setPIDTunings(pidKp, pidKi, pidKd);
    motors[1].setPIDTunings(pidKp, pidKi, pidKd);
    motors[2].setPIDTunings(pidKp, pidKi, pidKd);
  }
  if (varName == "ki") {
    pidKi = dynVars["ki"];
    driveType = DRIVE_TYPE_STOP;
    stopMotors();
    motors[0].setPIDTunings(pidKp, pidKi, pidKd);
    motors[1].setPIDTunings(pidKp, pidKi, pidKd);
    motors[2].setPIDTunings(pidKp, pidKi, pidKd);
  }
  if (varName == "kd") {
    pidKd = dynVars["kd"];
    driveType = DRIVE_TYPE_STOP;
    stopMotors();
    motors[0].setPIDTunings(pidKp, pidKi, pidKd);
    motors[1].setPIDTunings(pidKp, pidKi, pidKd);
    motors[2].setPIDTunings(pidKp, pidKi, pidKd);
  }
}