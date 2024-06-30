/// <reference types="web-bluetooth" />

import { Component, OnInit } from '@angular/core';
import { FormsModule } from '@angular/forms';
import nipplejs from 'nipplejs';

@Component({
  selector: 'app-motor-controller',
  standalone: true,
  imports: [FormsModule],
  templateUrl: './motor-controller.component.html',
  styleUrl: './motor-controller.component.css'
})

export class MotorControllerComponent implements OnInit {
  deviceName: string = "TWR1";
  bleService: string = '972830ca-08b4-4c05-8a09-786f366e4e7a';
  sensorCharacteristic: string = '62bebe3e-33a2-4ad8-90cb-ed91ad1d779f';
  cmdCharacteristic: string = '28d4c6aa-1559-4788-aaf7-a61b098318da';

  bleServer: BluetoothRemoteGATTServer = {} as any;
  bleServiceFound: BluetoothRemoteGATTService = {} as any;
  sensorCharacteristicFound: BluetoothRemoteGATTCharacteristic = {} as any;

  MOTOR_CMD: number = 1;
  MOVE_CMD: number = 2;
  ROTATE_CMD: number = 3;
  STOP_CMD: number = 4;
  DYNVAR_CMD: number = 20;
  LED_CMD: number = 30;

  MOVE_TYPE_FIXED: number = 0;
  MOVE_TYPE_ANGLED: number = 1;

  motor: Motor = {
    id: 1,
    speed: 30,
    speedType: "PWM"
  }

  dynVarName = "kp";
  dynVarValue = 0.0;

  moveDirectionCartesian = 0; // the cartesian direction as give by nipplejs, and used in Arduino code
  moveDirectionGeodetic = 0;  // the geodetic direction, or compass direction as used in the input
  moveSpeed = 1; // meter/second
  moveType = this.MOVE_TYPE_FIXED;

  bleState: string = "Checking Webbrowser bluetooth support...";

  joystick: any;

  onSendMotorCmdClick() {
    console.log("onSendMotorCommandClick");
    this.writeMotor();
  }

  onSendDynVarClick() {
    console.log("onSendDynVarClick");
    this.writeDynVar();
  }

  onSendMoveCmdClick() {
    console.log("onSendMoveCommandClick");
    this.writeMove();
  }

  onSendRotateCmdClick() {
    console.log("onSendRotateCommandClick");
    this.writeRotate();
  }

  onSendStopCmdClick() {
    console.log("onSendStopCommandClick");
    this.writeStop();
  }

  onBLEConnectClick() {
    console.log("onBLEConnnectClick");
    this.connectToDevice();
  }

  onBLEDisconnectClick() {
    console.log("onBLEDisconnnectClick");
    this.disconnectDevice();
  }

  ngOnInit(): void {
    this.isWebBluetoothEnabled();

    const joystick = nipplejs.create({
      zone: document.getElementById('joyDiv') as any,
      mode: 'static',
      position: {left: '50%', bottom: '250px'},
      color: 'blue'
    });
  joystick.on('move', this.onJoystickMove);
  joystick.on('end', this.onJoystickEnd);
}

  writeLed(value: number) {
    this.writeToCharacteristic(new Uint8Array([this.LED_CMD, value]));
  }

  writeMotor() {
    let motorNum = this.motor.id;
    let motorSpeed = this.motor.speed;
    let direction = (motorSpeed >= 0) ? 1 : 2; // 1 = cw, 2 = ccw
    let speedType = (this.motor.speedType == "PWM" ? 1 : 2); // 1 = PWM, 2 = RPM
    motorSpeed = Math.abs(motorSpeed);
    console.log(motorSpeed);
    this.writeToCharacteristic(new Uint8Array([this.MOTOR_CMD, motorNum, motorSpeed, direction, speedType]));
  }

  writeDynVar() {

    const buffer = new ArrayBuffer(10); 
    const dataView = new DataView(buffer);

    dataView.setInt32(0, this.DYNVAR_CMD, true); // true for little-endian

    // the dynVar name, two characters
    dataView.setUint8(4, this.dynVarName.charCodeAt(0));
    dataView.setUint8(5, this.dynVarName.charCodeAt(1));

    // Write the float value (4 bytes)
    dataView.setFloat32(6, this.dynVarValue, true);

    this.writeToCharacteristic(buffer);
  }

  writeMove() {
    const buffer = new ArrayBuffer(6);
    const view = new DataView(buffer);
    view.setUint8(0, this.MOVE_CMD);

    // The input is in geodetic/compass degrees, convert back to cartesian
    let angle = (450 - this.moveDirectionGeodetic) % 360;
    view.setUint16(1, angle, true); // Use little-endian format
    view.setUint16(3, this.moveSpeed, true);
    view.setUint8(5, this.moveType);

    this.writeToCharacteristic(buffer);
  }

  writeRotate() {
    const buffer = new ArrayBuffer(5);
    const view = new DataView(buffer);
    view.setUint8(0, this.ROTATE_CMD);
    
    // The input is in geodetic/compass degrees, convert back to geodetic
    let angle = (450 - this.moveDirectionGeodetic) % 360;
    view.setUint16(1, angle, true); // Use little-endian format
    view.setUint16(3, this.moveSpeed, true);

    this.writeToCharacteristic(buffer);
  }

  writeStop() {
    this.writeToCharacteristic(new Uint8Array([this.STOP_CMD]));
  }

  connectionTimer: any; 

  /**
   * BlueTooth functionality
   */
  isWebBluetoothEnabled() {
    if (!navigator.bluetooth) {
      this.bleState = "Web Bluetooth API not available";
      console.log("nok");
      return false
    }

    this.bleState = "Web Bluetooth API available!";
    console.log("ok");
    return true
  }

  connectToDevice() {
    console.log('Initializing Bluetooth...');
    navigator.bluetooth.requestDevice({
      filters: [{ name: this.deviceName }],
      optionalServices: [this.bleService]
    })
      .then(device => {
        console.log('Device Selected:', device.name);
        this.bleState = 'Connected to device ' + device.name;
        device.addEventListener('gattservicedisconnected', this.onDisconnected);

        if (device && device.gatt) {
          this.connectionTimer = setInterval(this.checkConnection, 1000);
          return device.gatt.connect();
        }
        else {
          return null;
        }
      })
      .then(gattServer => {
        if (gattServer) {
          this.bleServer = gattServer;
          console.log("Connected to GATT Server");
          return this.bleServer!.getPrimaryService(this.bleService);
        } else {
          return null;
        }
      })
      .then(service => {
        if (service) {
          this.bleServiceFound = service;
          console.log("Service discovered:", service.uuid);
          return service.getCharacteristic(this.sensorCharacteristic);
        } else {
          return null;
        }
      })
      .then(characteristic => {
        if (characteristic) {
          console.log("Characteristic discovered:", characteristic.uuid);
          this.sensorCharacteristicFound = characteristic;
          characteristic.addEventListener('characteristicvaluechanged', this.handleCharacteristicChange);
          characteristic.startNotifications();
          console.log("Notifications Started.");
          return characteristic.readValue();
        } else {
          return null;
        }
      })
      .then(value => {
        if (value) {
          console.log("Read value: ", value);
          const decodedValue = new TextDecoder().decode(value);
          console.log("Decoded value: ", decodedValue);
          //retrievedValue.innerHTML = decodedValue;
        }
      })
      .catch(error => {
        console.log('Error: ', error);
      })
  }

  disconnectDevice() {
    console.log("Disconnect Device.");
    if (this.bleServer && this.bleServer.connected) {
      if (this.sensorCharacteristicFound) {
        this.sensorCharacteristicFound.stopNotifications()
          .then(() => {
            console.log("Notifications Stopped");
            return this.bleServer.disconnect();
          })
          .then(() => {
            console.log("Device Disconnected");
            this.bleState = "Device Disconnected";
            clearInterval(this.connectionTimer)
          })
          .catch(error => {
            console.log("An error occurred:", error);
          });
      } else {
        console.log("No characteristic found to disconnect.");
      }
    } else {
      // Throw an error if Bluetooth is not connected
      console.error("Bluetooth is not connected.");
      window.alert("Bluetooth is not connected.")
    }
  }

  onDisconnected(event: any) {
    console.log('Device Disconnected:', event.target.device.name);
    this.bleState = "Device disconnected";

    this.connectToDevice();
  }

  handleCharacteristicChange(event: any) {
    const newValueReceived = new TextDecoder().decode(event.target.value);
    console.log("Characteristic value changed: ", newValueReceived);
    //retrievedValue.innerHTML = newValueReceived;
    //timestampContainer.innerHTML = getDateTime();
  }  

  writeToCharacteristic(data: any) {
    if (this.bleServer && this.bleServer.connected) {
      this.bleServiceFound.getCharacteristic(this.cmdCharacteristic)
        .then(characteristic => {
          console.log("Found the cmd characteristic: ", characteristic.uuid);
          return characteristic.writeValue(data);
        })
        .then(() => {
          //latestValueSent.innerHTML = value;
          console.log("Data written to cmd characteristic:", data);
        })
        .catch(error => {
          console.error("Error writing to cmd the characteristic: ", error);
        });
    } else {
      console.error("Bluetooth is not connected. Cannot write to cmd characteristic.")
      window.alert("Bluetooth is not connected. Cannot write to cmd characteristic. \n Connect to BLE first!")
    }
  }

  checkConnection = () => {
    //console.log("checkConnection");
    if (!(this.bleServer.connected)) {
      this.bleState = "Device Disconnected";
      clearInterval(this.connectionTimer);
    }
  }

  onJoystickMove = (e: any, data: any) => {
    console.log("Joystick event 'move' " + data.angle.degree);
    let angle = Math.floor(data.angle.degree);

    // Convert the cartesian angle to geodetic/compass degrees
    this.moveDirectionGeodetic = Math.floor((450 - data.angle.degree) % 360);
  
    if (this.bleServer && this.bleServer.connected) {
      this.writeMove();
    }
  }

  onJoystickEnd = (e: any, data: any) => {
    console.log("Joystick event 'end'");
    if (this.bleServer && this.bleServer.connected) {
      this.writeStop();
    }
  }

}

export interface Motor {
  id: number;
  speed: number;
  speedType: string;
}
