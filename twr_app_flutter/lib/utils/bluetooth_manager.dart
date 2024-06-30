import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';
import 'extra.dart';
import 'snackbar.dart';

/// BluetoothManager singleton
class BluetoothManager {
  // Private constructor
  BluetoothManager._privateConstructor() {
    _initialize();
  }

  // The one and only instance
  static final BluetoothManager _instance = BluetoothManager._privateConstructor();

  // Factory constructor to return the same instance every time
  factory BluetoothManager() {
    return _instance;
  }

  static const String _deviceName = "TWR1";
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  late StreamSubscription<BluetoothAdapterState> adapterStateStateSubscription;

  List<BluetoothDevice> systemDevices = [];
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  late StreamSubscription<List<ScanResult>> scanResultsSubscription;
  late StreamSubscription<bool> isScanningSubscription;

  /// Device
  BluetoothDevice? _device;
  int? rssi;
  int? mtuSize;
  BluetoothConnectionState connectionState =
      BluetoothConnectionState.disconnected;
  List<BluetoothService> services = [];
  bool isDiscoveringServices = false;
  bool isConnecting = false;
  bool isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState> connectionStateSubscription;
  late StreamSubscription<bool> isConnectingSubscription;
  late StreamSubscription<bool> isDisconnectingSubscription;
  late StreamSubscription<int> mtuSubscription;

  // StreamController for events
  final StreamController<String> _eventController = StreamController<String>.broadcast();
  // Stream to allow subscription to events
  Stream<String> get events => _eventController.stream;

  void _initialize() {
    /// adapter state
    adapterStateStateSubscription =
        FlutterBluePlus.adapterState.listen((state) {
          adapterState = state;
          _eventController.add('updatestate');
        });

    /// scan results
    scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      scanResults = results;

      for (ScanResult result in scanResults) {
        String deviceName = result.device.platformName;

        // connect when found
        if (deviceName == _deviceName) {
          connectDevice(result.device);
        }
        debugPrint('Found device: $deviceName');
      }
      _eventController.add('updatestate');
    }, onError: (e) {
      Snackbar.show(ABC.a, prettyException("Scan Error:", e), success: false);
      debugPrint('Scan Error: $e');
    });

    isScanningSubscription = FlutterBluePlus.isScanning.listen((state) {
      isScanning = state;
      _eventController.add('updatestate');
    });
  }

  void initDevice(BluetoothDevice btDevice) {
    _device = btDevice;
    connectionStateSubscription = btDevice.connectionState.listen((state) async {
      connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.disconnected) {
        _eventController.add('disconnected');
      }
      if (state == BluetoothConnectionState.connected && rssi == null) {
        rssi = await btDevice.readRssi();
      }

      _eventController.add('updatestate');
    });

    mtuSubscription = btDevice.mtu.listen((value) {
      mtuSize = value;
      _eventController.add('updatestate');
    });

    isConnectingSubscription = btDevice.isConnecting.listen((value) {
      isConnecting = value;
      _eventController.add('updatestate');
    });

    isDisconnectingSubscription = btDevice.isDisconnecting.listen((value) {
      isDisconnecting = value;
      _eventController.add('updatestate');
    });
  }

  Future connectDevice(BluetoothDevice btDevice) async {
    try {
      // initialize device events
      initDevice(btDevice);
      // connect
      await btDevice.connectAndUpdateStream();
      // get services
      services = await btDevice.discoverServices();
      _eventController.add('servicesdiscovered');

      Snackbar.show(ABC.a, "Connected to TWR1", success: true);
    } catch (e) {
      if (e is FlutterBluePlusException &&
          e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.a, prettyException("Connect Error:", e),
            success: false);
      }
      _eventController.add('updatestate');
    }
  }

  Future disconnectAndUpdateStream() async {
    return await _device?.disconnectAndUpdateStream();
  }

  Future onToggleConnect() async {
    if (connectionState == BluetoothConnectionState.connected) {
      try {
        await disconnectAndUpdateStream();
        Snackbar.show(ABC.a, "Disconnected from TWR1", success: true);
        _eventController.add('disconnected');

      } catch (e) {
        Snackbar.show(ABC.a, prettyException("Disconnect Error:", e),
            success: false);
        _eventController.add('updatestate');

      }
    } else {
      // Scan for device TWR1, _scanResultsSubscription will try to connect
      // if the device is found
      try {
        systemDevices = await FlutterBluePlus.systemDevices;
      } catch (e) {
        Snackbar.show(ABC.a, prettyException("System Devices Error:", e),
            success: false);
      }
      try {
        await FlutterBluePlus.startScan(
            withNames: [_deviceName], timeout: const Duration(seconds: 15));
      } catch (e) {
        Snackbar.show(ABC.a, prettyException("Start Scan Error:", e),
            success: false);
      }
    }
    _eventController.add('updatestate');
  }

  /// findCharacteristic
  BluetoothCharacteristic? findCharacteristic(Guid uuid) {
    for (BluetoothService s in services) {
      for (BluetoothCharacteristic c in s.characteristics) {
        if (c.characteristicUuid == uuid) {
          return c;
        }
      }
    }
    return null;
  }

}



