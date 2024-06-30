import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'bluetooth_manager.dart';

/// TWRManager singleton
class TWRManager {
  late BluetoothManager btm;

  // Private constructor
  TWRManager._privateConstructor() {
    btm = BluetoothManager();

    btm.events.listen((event) {
      // Start the twr sensorListener
      if (event == "servicesdiscovered") {
        // wordt (nog) niet gebruikt, uitgezet
        //startSensorListener();
      }

      // Stop the twr sensorListener
      if (event == "disconnected") {
        // wordt (nog) niet gebruikt, uitgezet
        //stopSensorListener();
      }
    });
  }
  bool sensorListenerStarted = false;

  // The one and only instance
  static final TWRManager _instance = TWRManager._privateConstructor();

  // Factory constructor to return the same instance every time
  factory TWRManager() {
    return _instance;
  }

  final String _cmdCharacteristicUUID = '28d4c6aa-1559-4788-aaf7-a61b098318da';
  BluetoothCharacteristic? _cmdCharacteristic;

  final String _sensorCharacteristicUUID = '62bebe3e-33a2-4ad8-90cb-ed91ad1d779f';
  BluetoothCharacteristic? _sensorCharacteristic;

  StreamSubscription<List<int>>? _sensorSubscription;

  ///
  /// Sensor listener
  ///
  Future startSensorListener() async {
    if (sensorListenerStarted) return;
    sensorListenerStarted = true;

    BluetoothCharacteristic? c = getSensorCharacteristic();
    if (c == null) return;

    await c.setNotifyValue(true);
    _sensorSubscription = c.lastValueStream.listen((value) {
      String stringValue = String.fromCharCodes(value);
      double receivedValue = double.tryParse(stringValue) ?? 0.0;
      debugPrint("!!!! mpu6050 $receivedValue !!!!");
    });
  }

  Future stopSensorListener() async {
    _sensorSubscription?.cancel();
    sensorListenerStarted = false;
  }

  ///
  /// BlueTooth Commands
  /// CMD_CHARACTERISTIC_UUID "28d4c6aa-1559-4788-aaf7-a61b098318da"
  ///
  int motorCommand = 1;
  int moveCommand = 2;
  int rotateCommand = 3;
  int stopCommand = 4;
  int resetCommand = 10;

  /// single motor command
  Future sendSingleMotorCmd(int motorId, int motorSpeed, int motorDirection, int speedType) async {
    BluetoothCharacteristic? c = getCmdCharacteristic();
    if (c == null) return;

    // Make byteList and write to characteristic
    final byteList = ByteData(5);

    byteList.setUint8(0, motorCommand); // MOTOR_CMD
    byteList.setUint8(1, motorId); // motor id
    byteList.setUint8(2, motorSpeed.abs()); // speed
    byteList.setUint8(3, motorDirection); // direction 1 = cw, 2 = ccw
    byteList.setUint8(4, speedType); // speedtype 1 = PWM, 2 = RPM

    //await c.write(byteList.buffer.asUint8List());
    await writeCommand(c, byteList);
  }

  /// move command
  Future sendMoveCmd(int moveDirection, int moveSpeed, int moveType) async {
    debugPrint('sendMoveCmd');

    BluetoothCharacteristic? c = getCmdCharacteristic();
    if (c == null) return;

    // Make byteList and write to characteristic
    final byteList = ByteData(6);
    byteList.setUint8(0, moveCommand);
    byteList.setUint16(1, moveDirection, Endian.little);
    byteList.setUint16(3, moveSpeed, Endian.little);
    byteList.setUint8(5, moveType); // 1 : rotate to angle, 2: fixed

    //await c.write(byteList.buffer.asUint8List());
    await writeCommand(c, byteList);
  }

  /// rotate command
  Future sendRotateCmd(int moveDirection, int moveSpeed) async {
    debugPrint('sendRotateCmd');

    BluetoothCharacteristic? c = getCmdCharacteristic();
    if (c == null) return;

    // Make byteList and write to characteristic
    final byteList = ByteData(5);
    byteList.setUint8(0, rotateCommand);
    byteList.setUint16(1, moveDirection, Endian.little);
    byteList.setUint16(3, moveSpeed, Endian.little);

    //await c.write(byteList.buffer.asUint8List());
    await writeCommand(c, byteList);
  }


  /// stop command
  Future sendStopCmd() async {
    debugPrint('sendStopCmd');

    BluetoothCharacteristic? c = getCmdCharacteristic();
    if (c == null) return;

    final byteList = ByteData(1);
    byteList.setUint8(0, stopCommand);

    //await c.write(byteList.buffer.asUint8List());
    await writeCommand(c, byteList);
  }

  /// stop command
  Future sendResetCmd() async {
    debugPrint('sendResetCmd');

    BluetoothCharacteristic? c = getCmdCharacteristic();
    if (c == null) return;

    final byteList = ByteData(1);
    byteList.setUint8(0, resetCommand);

    //await c.write(byteList.buffer.asUint8List());
    await writeCommand(c, byteList);
  }

  Future writeCommand(BluetoothCharacteristic c, ByteData byteList) async {
    await c.write(byteList.buffer.asInt8List());
  }

  BluetoothCharacteristic? getCmdCharacteristic() {
    _cmdCharacteristic ??= btm.findCharacteristic(Guid.fromString(_cmdCharacteristicUUID));
    return _cmdCharacteristic;
  }

  BluetoothCharacteristic? getSensorCharacteristic() {
    _sensorCharacteristic ??= btm.findCharacteristic(Guid.fromString(_sensorCharacteristicUUID));
    return _sensorCharacteristic;
  }
}
