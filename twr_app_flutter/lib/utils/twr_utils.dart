import 'dart:math';

enum Unit {
  meters,
  centimeters
}

class TwrUtils {
  static const double wheelRadiusMeters = 0.03;
  static const double gearRatio = 1;
  static const double maxRPM = 200;

  static int msToRpm(double speed, Unit unit) {
    double speedfactor = unit == Unit.centimeters ? 100 : 1;
    double ms = speed / speedfactor;

    // Constant for converting radians per second to RPM
    const double radianToRpm = 60 / (2 * pi);

    // Calculate angular velocity in radians per second
    double angularVelocityRadiansPerSecond = ms / wheelRadiusMeters;

    // Convert angular velocity to RPM
    double rpm = angularVelocityRadiansPerSecond * radianToRpm;

    // Adjust RPM for gear ratio
    double adjustedRpm = rpm / gearRatio;
    adjustedRpm = min(adjustedRpm, maxRPM);

    return adjustedRpm.toInt();
  }
}
