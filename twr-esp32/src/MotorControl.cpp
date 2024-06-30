#include <Arduino.h>
#include <cstdint>
#include <MotorControl.h>
#include <Streaming.h>

MotorControl::MotorControl(uint16_t IN1, uint16_t IN2, uint16_t PWM, uint16_t ENC2, int pwmChannel, bool debug)
  : targetPWM(0.0), direction(0), stopped(false), actualRPM(0),
  pidController(&actualRPM, &targetPWM, &targetRPM, 0.8, 0.5, 0.0, P_ON_M, DIRECT),
  speedType(1), pulseCount(0), previousPulseCount(0), previousMillis(0.0),
  IN1(IN1), IN2(IN2), PWM(PWM), ENC2(ENC2), pwmChannel(pwmChannel), debug(debug)
{
  pidController.SetMode(AUTOMATIC);
  pidController.SetOutputLimits(0, 255); // PWM output limits
}

void MotorControl::setPID() {
  if (targetRPM == 0) return;

  unsigned long currentMillis = millis();
  float elapsedTime = (currentMillis - previousMillis);
  previousMillis = currentMillis;

  noInterrupts();
  actualRPM = (pulseCount / (reductionRatio * ppr) * 60 * (1000 / elapsedTime));
  pulseCount = 0;
  interrupts();
  
  computePID();

  if (debug) Serial
    << "targetRPM: " << targetRPM
    << " actualRPM: " << actualRPM << endl;
}

void MotorControl::setSpeed(int speed, int speedType, int direction) {
  this->speedType = speedType;
  this->direction = direction;

  if (speedType == SPEED_TYPE_PWM)
  {
    targetRPM = 0;
    targetPWM = speed;
  }
  if (speedType == SPEED_TYPE_RPM)
  {
    targetPWM = 0;
    targetRPM = speed;
  }
}

void MotorControl::drive() {
  if (stopped && targetPWM == 0) return;

  int IN1State = (direction == CW) ? HIGH : LOW;

  digitalWrite(IN1, IN1State);
  digitalWrite(IN2, !IN1State);
  ledcWrite(pwmChannel, constrain(targetPWM, 0, 255));

  stopped = targetPWM == 0;
}

void MotorControl::stop() {
    targetPWM = 0;
    targetRPM = 0;
    resetPID();
}

void MotorControl::computePID() {
  pidController.Compute();
}

void MotorControl::setPIDTunings(double kp, double ki, double kd) {
  pidController.SetTunings(kp, ki, kd);
}

void MotorControl::resetPID() {
  pidController.SetMode(MANUAL); // Turn off the PID controller
  delay(10);
  pidController.SetMode(AUTOMATIC); // Turn it back on
}
