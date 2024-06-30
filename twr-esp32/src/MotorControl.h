#include <Arduino.h>
#include <cstdint>
#include <PID_v1.h>

class MotorControl {
private:
  bool debug = false;
  // Motor characteristics (https://www.waveshare.com/wiki/DCGM-N20-12V-EN-200RPM) 
  double reductionRatio = 150;
  int ppr = 7; // pulse per revolution
  

public:
  #define CW 1
  #define CCW 2
  #define SPEED_TYPE_PWM 1
  #define SPEED_TYPE_RPM 2

  // pins
  uint16_t IN1;         // pin input 1    
  uint16_t IN2;         // pin input 2    
  uint16_t PWM;         // pin PWM control
  uint16_t ENC2;        // pin encoder C2
  int pwmChannel;       // PWM channel
  // Driving & PID
  int speedType;
  double targetPWM;
  double targetRPM;
  double actualRPM;
  int direction;
  bool stopped;
  volatile long pulseCount;
  long previousPulseCount;
  long previousMillis;
  PID pidController;

  MotorControl(uint16_t IN1, uint16_t IN2, uint16_t PWM, uint16_t ENC2, int pwmChannel, bool debug);
  void setPID();
  void setSpeed(int speed, int speedType, int direction);
  void drive();
  void stop();
  void computePID();
  void setPIDTunings(double kp, double ki, double kd);
  void resetPID();

};