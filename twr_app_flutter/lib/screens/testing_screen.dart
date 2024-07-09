import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:twr_app_flutter/utils/twr_manager.dart';
import '../utils/bluetooth_manager.dart';
import '../utils/snackbar.dart';
//import '../utils/twr_utils.dart';
import '../widgets/d_button.dart';
import '../widgets/d_input.dart';
import 'package:provider/provider.dart';
import '../models/screen_model.dart';

class TestingScreen extends StatefulWidget {
  const TestingScreen({super.key});

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  // The BluetoothManager will handle all the bluetooth stuff
  final BluetoothManager btm = BluetoothManager();
  // The TWRMangers will handle commands for the ESP32
  final TWRManager twr = TWRManager();

  /// Event listener for updating screen state when bluetooth things happen
  StreamSubscription<String>? _btmSubscription;

  late Timer _timer;

  /// initState()
  @override
  void initState() {
    super.initState();

    // Set default values
    if (mounted) {
      setState(() {
        ScreenModel screenModel =
            Provider.of<ScreenModel>(context, listen: false);

        /// Single Speed
        screenModel.updateValue('single_motor_id', '1');
        screenModel.updateValue('single_motor_speed', '70');
        screenModel.updateValue('single_motor_speed_type', 'RPM');

        /// Move
        screenModel.updateValue('move_direction', '0');
        screenModel.updateValue('move_speed', '70');

        /// Square
        screenModel.updateValue('pattern_distance', '80');
        screenModel.updateValue('pattern_speed', '70');
      });
    }

    _btmSubscription = btm.events.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });

    if (!isConnected) {
      btm.onToggleConnect();
    }
  }

  /// dispose()
  @override
  void dispose() {
    _btmSubscription?.cancel();
    _timer.cancel();
    super.dispose();
  }

  bool get isConnected {
    return btm.connectionState == BluetoothConnectionState.connected;
  }

  /// Scan and connect or disconnect
  Future onToggleConnect() async {
    await btm.onToggleConnect();
  }

  Future _sendSingleMotorCmd() async {
    // Get values from screen
    ScreenModel screenModel = Provider.of<ScreenModel>(context, listen: false);
    int motorId = int.parse(screenModel.getValue('single_motor_id'));
    int motorSpeed = int.parse(screenModel.getValue('single_motor_speed'));
    int motorDirection = motorSpeed > 0 ? 1 : 2;
    int speedType =
        screenModel.getValue('single_motor_speed_type') == 'PWM' ? 1 : 2;

    await twr.sendSingleMotorCmd(
        motorId, motorSpeed, motorDirection, speedType);
  }

  Future _sendMoveCmd() async {
    // Get values from screen
    ScreenModel screenModel = Provider.of<ScreenModel>(context, listen: false);
    int moveDirection = int.parse(screenModel.getValue('move_direction'));
    // The input is in geodetic/compass degrees, convert back to cartesian
    moveDirection = (450 - moveDirection) % 360;
    int moveSpeed = int.parse(screenModel.getValue('move_speed'));
    int moveType = 2;

    await twr.sendMoveCmd(moveDirection, moveSpeed, moveType);
  }

  Future _sendStopCmd() async {
    _timer.cancel();
    twr.sendStopCmd();
  }

  String _selectedPattern = "Square";
  Future _onPatternSelected(String? pattern) async {
    setState(() {
      _selectedPattern = pattern ?? "Circle";
    });
  }

  Future _moveInPattern() async {
    if (_selectedPattern == "Square") {
      await _moveInSquare();
    }
    if (_selectedPattern == "Circle") {
      await _moveInCircle();
    }
  }

  Future _moveInSquare() async {
    // Get values from screen
    ScreenModel screenModel = Provider.of<ScreenModel>(context, listen: false);
    int squareDistance = int.parse(screenModel.getValue('pattern_distance'));
    int squareSpeed = int.parse(screenModel.getValue('pattern_speed'));

    double wheelRadius = 0.03;
    double meterPerSecond = squareSpeed * 2 * pi * wheelRadius;

    double waitTime = squareDistance / 100.0 * 60.0 / meterPerSecond * 1000.0;
    debugPrint("Square");
    debugPrint("waitTime: $waitTime.toInt()");

    List<int> angles = [0, 90, 180, 270];
    int curAngleIndex = 0;

    // First movement
    await twr.sendStopCmd();
    await twr.sendMoveCmd((450 -angles[curAngleIndex]) % 360, squareSpeed, 2);
    curAngleIndex++;

    _timer = Timer.periodic(Duration(milliseconds: waitTime.toInt()), (Timer timer) async {
      int angle = angles[curAngleIndex];
      debugPrint("Square: $angle");
      // The input is in geodetic/compass degrees, convert back to cartesian
      angle = (450 - angle) % 360;

      await twr.sendStopCmd();
      await Future.delayed(const Duration(milliseconds: 50));
      await twr.sendMoveCmd(angle, squareSpeed, 2);
      curAngleIndex++;
      if (curAngleIndex > 3) {
        curAngleIndex = 0;
      }
    });
  }

  ///
  /// circleRadius in cm
  /// speed in cm/s
  Future _moveInCircle() async {
    // Get values from screen
    ScreenModel screenModel = Provider.of<ScreenModel>(context, listen: false);
    int circleRadius = int.parse(screenModel.getValue('pattern_distance'));
    int speed = int.parse(screenModel.getValue('pattern_speed'));

    //int rpm = TwrUtils.msToRpm(speed.toDouble(), Unit.centimeters);

    // circuference of circle with circleRadius
    double circumference = 2 * pi * circleRadius * 100;
    // total time needed to compleet circle for given speed in cm/s
    double totalTime = circumference / speed / 100.0;
    // time interval of 50 ms
    double interval = 50;

    // needed angle increments per circle
    double increments = totalTime / interval * 1000;
    // angle increment in radians
    double angleIncrement = 2 * pi / increments;
    angleIncrement = angleIncrement * 180 / pi;

    debugPrint("angleIncrement: $angleIncrement");
    //return;

    await twr.sendStopCmd();
    double angle = 0;
    _timer = Timer.periodic(Duration(milliseconds: interval.toInt()), (Timer timer) async {
      double moveAngle = (450.0 - angle) % 360.0;
      //debugPrint("moveAngle: $moveAngle");
      await twr.sendMoveCmd(moveAngle.round(), speed, 2);
      angle += angleIncrement;
    });
  }


  ///
  /// UI
  ///
  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called
    return ScaffoldMessenger(
        key: Snackbar.snackBarKeyA,
        child: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// BLE buttons
                BLERow(onPressed: onToggleConnect, isConnected: isConnected),

                /// Single Speed
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Single Speed', style: TextStyle(fontSize: 16)),
                ),
                SingleSpeedRow(onPressed: _sendSingleMotorCmd),

                /// Move
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Move', style: TextStyle(fontSize: 16)),
                ),
                MoveRow(onPressed: _sendMoveCmd),

                /// Pattern
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Pattern', style: TextStyle(fontSize: 16)),
                ),
                PatternRow(onPressed: _moveInPattern, selectedPatern: _selectedPattern, onPatternSelected: _onPatternSelected,),

                /// Stop
                const SizedBox(height: 26),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                        onPressed: _sendStopCmd,
                        icon: const Icon(Icons.cancel),
                        iconSize: 50,
                        color: Colors.red),
                  ],
                )
              ],
            ),
          )),
        ));
  }
}

///
/// Components
///

/// BLERow
class BLERow extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isConnected;

  const BLERow({super.key, required this.onPressed, required this.isConnected});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        DButton(
            onPressed: onPressed,
            label: isConnected ? 'Disconnect' : 'Connect'),
        const SizedBox(width: 8),
        Text(isConnected ? "Connected" : "Disconnected"),
      ],
    );
  }
}

/// SingleSpeedRow
class SingleSpeedRow extends StatelessWidget {
  final VoidCallback onPressed;

  const SingleSpeedRow({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: DInput(
            fieldKey: 'single_motor_id',
            label: 'Motor',
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: DInput(
            fieldKey: 'single_motor_speed',
            label: 'Speed',
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: DInput(
            fieldKey: 'single_motor_speed_type',
            label: 'Type',
          ),
        ),
        const SizedBox(width: 8),
        DButton(
          onPressed: onPressed,
          label: 'Send',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// MoveRow
class MoveRow extends StatelessWidget {
  final VoidCallback onPressed;

  const MoveRow({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: DInput(
            fieldKey: 'move_direction',
            label: 'Direction',
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: DInput(
            fieldKey: 'move_speed',
            label: 'Speed',
          ),
        ),
        const SizedBox(width: 8),
        DButton(
          onPressed: onPressed,
          label: 'Send',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

/// PatternRow
class PatternRow extends StatelessWidget {
  final VoidCallback onPressed;
  final Function(String?) onPatternSelected;
  final String selectedPatern;

  const PatternRow({super.key, required this.onPressed, required this.selectedPatern, required this.onPatternSelected});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
            child: DropdownButton<String>(
              value: selectedPatern,
              icon: const Icon(Icons.arrow_downward),
              elevation: 16,
              items: <String>['Square', 'Circle']
                  .map<DropdownMenuItem<String>>((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                onPatternSelected(newValue);
              },
            )
        ),
        const Expanded(
          child: DInput(
            fieldKey: 'pattern_distance',
            label: 'Distance (cm)',
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: DInput(
            fieldKey: 'pattern_speed',
            label: 'Speed (cm/s)',
          ),
        ),
        const SizedBox(width: 8),
        DButton(
          onPressed: onPressed,
          label: 'Start',
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}
