import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:twr_app_flutter/utils/twr_manager.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/bluetooth_manager.dart';
import '../utils/snackbar.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:wifi_iot/wifi_iot.dart';

class JoystickScreen extends StatefulWidget {
  const JoystickScreen({super.key});

  @override
  State<JoystickScreen> createState() => _JoystickScreenState();
}

class _JoystickScreenState extends State<JoystickScreen> {
  // The BluetoothManager will handle all the bluetooth stuff
  final BluetoothManager btm = BluetoothManager();
  // The TWRManager will handle commands for the ESP32
  final TWRManager twr = TWRManager();

  /// Event listener for updating screen state when bluetooth things happen
  StreamSubscription<String>? _btmSubscription;

  // Event listener for Compass
  StreamSubscription<CompassEvent>? _compassSubscription;

  late WebViewController webViewController;

  bool _stopped = true;

  /// initState()
  @override
  void initState() {
    super.initState();

    _btmSubscription = btm.events.listen((event) {
      if (mounted) {
        setState(() {});
      }
    });

    _compassSubscription = FlutterCompass.events!.listen((event) {
      _processCompassEvent(event);
    });
    _compassSubscription!.pause();

    if (!isConnected) {
      btm.onToggleConnect();
    }

    /// WebView
    webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            // Update loading bar.
          },
          onPageStarted: (String url) {
            //debugPrint("WebView onPageStarted");
          },
          onPageFinished: (String url) {
            //debugPrint("WebView onPageFinished");
          },
          onHttpError: (HttpResponseError error) {
            // retry connectCamera()
            connectCamera();
          },
          onWebResourceError: (WebResourceError error) {
            // retry connectCamera()
            connectCamera();
          },
          onNavigationRequest: (NavigationRequest request) {
            //debugPrint("WebView onNavigationRequest");
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString("<div style='text-align: center; font-size: 50px; margin-top: 150px;'>Waiting for camera stream...</div>");

    connectCamera();
  }

  Future<void> connectCamera() async {
    bool connected = false;
    String? ssid = await WiFiForIoTPlugin.getSSID();
    if (ssid != "twrcamera") {
      await WiFiForIoTPlugin.connect("twrcamera", password: "IwwodTWRCAMNu!", joinOnce: true, security: NetworkSecurity.WPA);
    }

    Future.delayed(const Duration(seconds: 3), () {
      webViewController.loadRequest(Uri.parse("http://192.168.4.1:81/view"));
    });
  }
  /// dispose()
  @override
  void dispose() {
    _btmSubscription?.cancel();
    _compassSubscription?.cancel();
    //WiFiForIoTPlugin.disconnect();
    super.dispose();
  }

  bool get isConnected {
    return btm.connectionState == BluetoothConnectionState.connected;
  }

  /// joystick
  double _jsX = 0;
  double _jsY = 0;
  final JoystickMode _joystickMode = JoystickMode.all;

  Future _updateJsCoords(double x, double y) async {
    debugPrint("updateJsCoords");

    if (_jsX == x && _jsY == y) return;

    _jsX = x;
    _jsY = y;

    if (_jsX == 0 && _jsY == 0) {
      await _sendStopCmd();
    } else {
      await _sendMoveCmd();
    }
  }

  Future _joystickDragStart() async {
    _stopped = false;
    debugPrint("dragstart");
  }

  Future _joystickDragEnd() async {
    _stopped = true;
    debugPrint("dragend");
    //await _sendStopCmd();
  }

  /// Speed
  double _speed = 75;

  Future _updateSpeed(double s) async {
    setState(() {
      _speed = s;
    });
  }

  /// Movetype
  static const int moveTypeMoveTo = 0;
  static const int moveTypeTurnTo = 1;
  static const int moveTypeRotate = 2;
  static const int moveTypeFollow = 3;

  int _moveType = moveTypeMoveTo;

  final List<Widget> _moveTypes = <Widget>[
    const Text('Move To'),
    const Text('Turn To'),
    const Text('Rotate'),
    //const Text('Follow'),
  ];

  final List<bool> _selectedMoveType = <bool>[true, false, false];

  Future _updateMoveType(int index) async {
    setState(() {
      for (int i = 0; i < _selectedMoveType.length; i++) {
        if (i == index) {
          _selectedMoveType[i] = true;
          _moveType = i;

          debugPrint(_moveType.toString());
        } else {
          _selectedMoveType[i] = false;
        }
      }
    });

    // Calculate the difference between the real heading and
    // the north of the robot, assuming the device is held in
    // the same up orientation as the robot. Used to offset the heading
    // for moveTypeFollow.
    final CompassEvent event = await FlutterCompass.events!.first;
    // heading in cartesian degrees
    double crtDegrees = compassToCartesianHeading(event.heading!);
    // offset heading compared to cartesian north (90)
    _offsetHeading = (90.0 - crtDegrees);

    // Resume or Pause Compass events
    if (_moveType == moveTypeFollow) {
      _compassSubscription?.resume();
    } else {
      _compassSubscription?.pause();
    }
  }

  /// Webview

  /// Compass
  int _lastCompassEvent = DateTime.now().millisecond;
  final int _compassEventInterval = 100;
  double _offsetHeading = 0;
  double _initialHeading = 0;

  Future _processCompassEvent(CompassEvent event) async {
    if (_lastCompassEvent != 0 &&
        DateTime.now().millisecondsSinceEpoch - _lastCompassEvent <
            _compassEventInterval) return;
    double crtDegrees = compassToCartesianHeading(event.heading!);

    double robotHeading = (crtDegrees + _offsetHeading) % 360;
    debugPrint("offset: $_offsetHeading robot: $robotHeading");

    if (_mtfMoving) {
      await twr.sendMoveCmd(robotHeading.toInt(), _speed.toInt(), 1);
    } else {
      twr.sendStopCmd();
    }

    _lastCompassEvent = DateTime.now().millisecondsSinceEpoch;
  }

  double compassToCartesianHeading(double compassHeading) {
    // heading in geodetic degrees
    double geoDegrees = (compassHeading + 360) % 360;
    // heading in cartesian degrees
    double crtDegrees = (450 - geoDegrees) % 360;

    return crtDegrees;
  }

  // MoveType Follow
  bool _mtfMoving = false;

  void _mtfTapDown() {
    setState(() {
      debugPrint("tapdown");
      _mtfMoving = true;
    });
  }

  void _mtfTapUp() {
    setState(() {
      debugPrint("tapup");
      _mtfMoving = false;
    });
  }

  void _mtfTapCancel() {
    setState(() {
      debugPrint("tapcancel");
      _mtfMoving = false;
    });
  }

  /// TWR Commands

  Future _sendMoveCmd() async {
    if (_stopped) return;
    //debugPrint('sendMoveCmd');

    // -y because y is reversed (north is negative)
    // +360 because we want only positive degrees
    double moveDirection = ((atan2(-_jsY, _jsX) * 180 / pi) + 360) % 360;
    //debugPrint('x: $_jsX y: $_jsY angle: $moveDirection');

    // If _adjustToDeviceYaw is ticked, calculate the difference
    // between current compass heading and initial heading
    // and add to the moveDirection, to correct for users
    // position
    if (_adjustToDeviceYaw) {
      final CompassEvent event = await FlutterCompass.events!.first;
      final currentHeading = compassToCartesianHeading(event.heading!);
      final diffFromInitial = currentHeading - _initialHeading;

      moveDirection = (moveDirection + diffFromInitial) % 360;
    }

    // _moveType
    // 0, moveTypeMoveTo, moveCmd with moveType 1 in ESP3
    // 1, moveTypeTurnTo, moveCmd with moveType 2 in ESP3
    // 2, moveTypeRotate, rotateCmd in ESP3
    // 3, moveTypeFollow is handled in _processCompassEvent
    switch (_moveType) {
      case moveTypeMoveTo:
        await twr.sendMoveCmd(moveDirection.toInt(), _speed.toInt(), 2);
        break;
      case moveTypeTurnTo:
        await twr.sendMoveCmd(moveDirection.toInt(), _speed.toInt(), 1);
        break;
      case moveTypeRotate:
        await twr.sendRotateCmd(moveDirection.toInt(), _speed.toInt());
        break;
    }
  }

  Future _sendStopCmd() async {
    //debugPrint('sendStopCmd');
    await twr.sendStopCmd();
  }

  // Reset the initialHeading of the compass
  Future _resetCmd() async {
    final CompassEvent event = await FlutterCompass.events!.first;
    _initialHeading = compassToCartesianHeading(event.heading!);

    twr.sendResetCmd();
  }

  // Adjust direction from joystick to orientation device
  bool _adjustToDeviceYaw = false;
  Future _onAdjustToDeviceYawChanged(bool? value) async {
    setState(() {
      _adjustToDeviceYaw = value!;
    });

    final CompassEvent event = await FlutterCompass.events!.first;
    _initialHeading = compassToCartesianHeading(event.heading!);
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
          body: Column(
            children: [
              /// WebView
              Expanded(child: WebViewWidget(controller: webViewController)),
              Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        /// Speed slider
                        SpeedSlider(
                            updateSpeed: _updateSpeed, currentValue: _speed),
                        Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 1,
                                child: MoveTypeToggle(
                                    updateMoveType: _updateMoveType,
                                    selectedMoveType: _selectedMoveType,
                                    moveTypes: _moveTypes),
                              ),
                              // Joystick or Tap Icon
                              if (_moveType == moveTypeFollow)
                                MtfButton(
                                    onTapDown: _mtfTapDown,
                                    onTapUp: _mtfTapUp,
                                    onTapCancel: _mtfTapCancel)
                              else
                                Js(
                                    updateJsCoords: _updateJsCoords,
                                    joystickDragStart: _joystickDragStart,
                                    joystickDragEnd: _joystickDragEnd,
                                    joystickMode: _joystickMode),
                              Expanded(
                                flex: 1,
                                child: RightButtons(
                                  onStopPressed: _sendStopCmd,
                                  onResetPressed: _resetCmd,
                                  onAdjustToDeviceYawChanged: _onAdjustToDeviceYawChanged,
                                  adjustToDeviceYaw: _adjustToDeviceYaw,
                                ),
                              )
                            ]),
                      ],
                    ),
                  ))
            ],
          ),
        ));
  }
}

///
/// Components
///

/// Movetype toggle
class MoveTypeToggle extends StatelessWidget {
  final Function(int) updateMoveType;
  final List<bool> selectedMoveType;
  final List<Widget> moveTypes;

  const MoveTypeToggle(
      {super.key,
      required this.updateMoveType,
      required this.selectedMoveType,
      required this.moveTypes});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ToggleButtons(
        direction: Axis.vertical,
        onPressed: (int index) {
          updateMoveType(index);
        },
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        selectedBorderColor: Colors.red[700],
        selectedColor: Colors.white,
        fillColor: Colors.red[200],
        color: Colors.red[400],
        constraints: const BoxConstraints(
          minHeight: 35.0,
          minWidth: 60.0,
        ),
        isSelected: selectedMoveType,
        children: moveTypes,
      ),
    );
  }
}

/// Speed slider
class SpeedSlider extends StatelessWidget {
  const SpeedSlider(
      {super.key, required this.updateSpeed, required this.currentValue});
  final Function(double) updateSpeed;
  final double currentValue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Slider(
          value: currentValue,
          max: 200,
          divisions: 20,
          label: currentValue.round().toString(),
          onChanged: (double value) {
            updateSpeed(value);
          }),
    );
  }
}

/// Joystick
class Js extends StatelessWidget {
  final Function(double, double) updateJsCoords;
  final Function() joystickDragStart;
  final Function() joystickDragEnd;
  final JoystickMode joystickMode;

  const Js(
      {super.key, required this.updateJsCoords, required this.joystickMode, required this.joystickDragStart, required this.joystickDragEnd});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Joystick(
        onStickDragStart: joystickDragStart,
        onStickDragEnd: joystickDragEnd,
          includeInitialAnimation: false,
          base: JoystickBase(
            size: 180,
              decoration: JoystickBaseDecoration(
                color: const Color.fromARGB(255, 211, 211, 211),
                drawArrows: true,
                drawOuterCircle: false,
                drawInnerCircle: false,
              ),
              arrowsDecoration: JoystickArrowsDecoration(
                color: Colors.grey,
                enableAnimation: false,
              )),
          stick: JoystickStick(
            decoration: JoystickStickDecoration(
              color: Colors.grey,
            ),
          ),
          mode: joystickMode,
          listener: (details) {
            updateJsCoords(details.x, details.y);
          }),
    );
  }
}

class MtfButton extends StatelessWidget {
  final VoidCallback onTapDown;
  final VoidCallback onTapUp;
  final VoidCallback onTapCancel;

  const MtfButton(
      {super.key,
      required this.onTapDown,
      required this.onTapUp,
      required this.onTapCancel});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
        onTapDown: (_) {
          onTapDown();
        },
        onTapUp: (_) {
          onTapUp();
        },
        onTapCancel: () {
          onTapCancel();
        },
        child: const IconButton(
          icon: Icon(Icons.radio_button_checked_outlined),
          iconSize: 184,
          onPressed: null,
        ));
  }
}

class LeftButtons extends StatelessWidget {
  const LeftButtons({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(crossAxisAlignment: CrossAxisAlignment.end, children: []);
  }
}

class RightButtons extends StatelessWidget {
  final VoidCallback onStopPressed;
  final VoidCallback onResetPressed;
  final Function(bool?) onAdjustToDeviceYawChanged;
  final bool adjustToDeviceYaw;

  const RightButtons({
    super.key,
    required this.onStopPressed,
    required this.onResetPressed,
    required this.onAdjustToDeviceYawChanged,
    required this.adjustToDeviceYaw,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
      IconButton(
        onPressed: onStopPressed,
        icon: const Icon(Icons.cancel),
        iconSize: 50,
        color: Colors.red,
      ),
      const Text('Adj2Pos'),
      Switch(value: adjustToDeviceYaw, onChanged: onAdjustToDeviceYawChanged),
      TextButton(
        onPressed: onResetPressed,
        child: const Text('Reset'),
      ),
    ]);
  }
}
