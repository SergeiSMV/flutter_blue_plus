import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../widgets/service_tile.dart';
import '../widgets/characteristic_tile.dart';
import '../widgets/descriptor_tile.dart';
import '../utils/snackbar.dart';
import '../utils/extra.dart';

class DeviceScreen extends StatefulWidget {
  final BluetoothDevice device;

  const DeviceScreen({Key? key, required this.device}) : super(key: key);

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  int? _rssi;
  int? _mtuSize;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isDiscoveringServices = false;
  bool _isConnecting = false;
  bool _isDisconnecting = false;

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<bool> _isConnectingSubscription;
  late StreamSubscription<bool> _isDisconnectingSubscription;
  late StreamSubscription<int> _mtuSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((state) async {
      _connectionState = state;
      if (state == BluetoothConnectionState.connected) {
        _services = []; // must rediscover services
      }
      if (state == BluetoothConnectionState.connected && _rssi == null) {
        _rssi = await widget.device.readRssi();
      }
      if (mounted) {
        setState(() {});
      }
    });

    _mtuSubscription = widget.device.mtu.listen((value) {
      _mtuSize = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isConnectingSubscription = widget.device.isConnecting.listen((value) {
      _isConnecting = value;
      if (mounted) {
        setState(() {});
      }
    });

    _isDisconnectingSubscription = widget.device.isDisconnecting.listen((value) {
      _isDisconnecting = value;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    _isConnectingSubscription.cancel();
    _isDisconnectingSubscription.cancel();
    super.dispose();
  }

  bool get isConnected {
    return _connectionState == BluetoothConnectionState.connected;
  }

  Future onConnectPressed() async {
    try {
      await widget.device.connectAndUpdateStream();
      Snackbar.show(ABC.c, "Connect: Success", success: true);
    } catch (e) {
      if (e is FlutterBluePlusException && e.code == FbpErrorCode.connectionCanceled.index) {
        // ignore connections canceled by the user
      } else {
        Snackbar.show(ABC.c, prettyException("Connect Error:", e), success: false);
      }
    }
  }

  Future onCancelPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream(queue: false);
      Snackbar.show(ABC.c, "Cancel: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Cancel Error:", e), success: false);
    }
  }

  Future onDisconnectPressed() async {
    try {
      await widget.device.disconnectAndUpdateStream();
      Snackbar.show(ABC.c, "Disconnect: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Disconnect Error:", e), success: false);
    }
  }

  Future onDiscoverServicesPressed() async {
    if (mounted) {
      setState(() {
        _isDiscoveringServices = true;
      });
    }
    try {
      _services = await widget.device.discoverServices();
      Snackbar.show(ABC.c, "Discover Services: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Discover Services Error:", e), success: false);
    }
    if (mounted) {
      setState(() {
        _isDiscoveringServices = false;
      });
    }
  }

  Future onRequestMtuPressed() async {
    try {
      await widget.device.requestMtu(112, predelay: 0);
      Snackbar.show(ABC.c, "Request Mtu: Success", success: true);
    } catch (e) {
      Snackbar.show(ABC.c, prettyException("Change Mtu Error:", e), success: false);
    }
  }

  
  List<Widget> _buildServiceTiles(BuildContext context, BluetoothDevice d) {
    return _services.map((s) => ServiceTile(service: s, characteristicTiles: s.characteristics.map((c) => _buildCharacteristicTile(c)).toList(),
          ),
        )
        .toList();
  }

  
  CharacteristicTile _buildCharacteristicTile(BluetoothCharacteristic c) {
    return CharacteristicTile(
      characteristic: c,
      descriptorTiles: c.descriptors.map((d) => DescriptorTile(descriptor: d)).toList(),
    );
  }

  Widget buildSpinner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14.0),
      child: AspectRatio(
        aspectRatio: 1.0,
        child: CircularProgressIndicator(
          backgroundColor: Colors.black12,
          color: Colors.black26,
        ),
      ),
    );
  }

  Widget buildRemoteId(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text('${widget.device.remoteId}'),
    );
  }

  Widget buildRssiTile(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        isConnected ? const Icon(Icons.bluetooth_connected) : const Icon(Icons.bluetooth_disabled),
        Text(((isConnected && _rssi != null) ? '${_rssi!} dBm' : ''), style: Theme.of(context).textTheme.bodySmall)
      ],
    );
  }

  Widget buildGetServices(BuildContext context) {
    return IndexedStack(
      index: (_isDiscoveringServices) ? 1 : 0,
      children: <Widget>[
        TextButton(
          child: const Text("Get Services"),
          onPressed: onDiscoverServicesPressed,
        ),
        const IconButton(
          icon: SizedBox(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.grey),
            ),
            width: 18.0,
            height: 18.0,
          ),
          onPressed: null,
        )
      ],
    );
  }

  Widget buildMtuTile(BuildContext context) {
    return ListTile(
        title: const Text('MTU Size'),
        subtitle: Text('$_mtuSize bytes'),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: onRequestMtuPressed,
        ));
  }

  Widget buildConnectButton(BuildContext context) {
    return Row(children: [
      if (_isConnecting || _isDisconnecting) buildSpinner(context),
      TextButton(
          onPressed: _isConnecting ? onCancelPressed : (isConnected ? onDisconnectPressed : onConnectPressed),
          child: Text(
            _isConnecting ? "CANCEL" : (isConnected ? "DISCONNECT" : "CONNECT"),
            style: Theme.of(context).primaryTextTheme.labelLarge?.copyWith(color: Colors.black),
          ))
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: Snackbar.snackBarKeyC,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.device.platformName),
          actions: [buildConnectButton(context)],
        ),
        body: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              buildRemoteId(context),
              ListTile(
                leading: buildRssiTile(context),
                title: Text('Device is ${_connectionState.toString().split('.')[1]}.'),
                trailing: buildGetServices(context),
              ),
              buildMtuTile(context),
              // ..._buildServiceTiles(context, widget.device),
              TextButton(
                onPressed: () async {
                  
                  for (BluetoothService service in _services) {
                    if (service.uuid.toString() == 'ffe0') {
                      var characteristics = service.characteristics;
                      for (BluetoothCharacteristic characteristic in characteristics) {
                        if (characteristic.uuid.toString() == 'ffe1') {
                          await characteristic.write(
                          [170, 85, 144, 235, 151, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 17],
                          withoutResponse: false);

                          // characteristic.lastValueStream.listen((value) {
                          //   value.contains(190) ? print('value190: $value') : null;
                          //   List<int> hexFormat = value.map((v) => int.parse('0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}')).toList();
                          //   String deviceName = utf8.decode(hexFormat.sublist(46, 46 + 16));
                          //   print('Device name: $deviceName');
                          //   String devicePasscode = utf8.decode(hexFormat.sublist(62, 62 + 16));
                          //   print('Device passcode: $devicePasscode');
                          // });

                          /*
                          await characteristic.setNotifyValue(true).then((_) {
                            characteristic.lastValueStream.listen((value) async {
                              value.contains(190) ? print('value190: $value') : null;
                              List<int> hexFormat = value.map((v) => int.parse('0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}')).toList();
                              String deviceName = utf8.decode(hexFormat.sublist(46, 46 + 16));
                              print('Device name: $deviceName');
                              String devicePasscode = utf8.decode(hexFormat.sublist(62, 62 + 16));
                              print('Device passcode: $devicePasscode');
                              /*
                              Uint16List input = Uint16List.fromList(hexFormat);
                              ByteData bd = input.buffer.asByteData();
                              try {
                                // Смещение 130
                                int offset = 130;
                                // Чтение 16-битного значения int16 с позиции 130
                                int result = bd.getInt16(offset + 46, Endian.little);
                                print('temp DEVICE_INFO: ${result}');
                              } catch (e) {
                                null;
                              }
                              */
                            });
                          });
                          */
                        }
                      }
                    }
                  }
                  
                }, 
                child: Text('COMMAND_DEVICE_INFO')
              ),
              TextButton(
                onPressed: () async {
                  
                  for (BluetoothService service in _services) {
                    if (service.uuid.toString() == 'ffe0') {
                      var characteristics = service.characteristics;
                      for (BluetoothCharacteristic characteristic in characteristics) {
                        if (characteristic.uuid.toString() == 'ffe1') {
                          await characteristic.write(
                          [170, 85, 144, 235, 150, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 16],
                          withoutResponse: false);
                          await characteristic.setNotifyValue(true).then((_) {
                            characteristic.lastValueStream.listen((value) async {
                              // List<int> hexFormat = value.map((v) => int.parse('0x${v.toRadixString(16).padLeft(2, '0').toUpperCase()}')).toList();
                              
                              Uint16List input = Uint16List.fromList(value);
                              ByteData bd = input.buffer.asByteData();
                              try {

                                /*
                                КОД ИЗ ble.cpp

                                uint8_t offset = 0;
                                if (this->protocol_version_ == PROTOCOL_VERSION_JK02_32S) {
                                  frame_version = FRAME_VERSION_JK02_32S;
                                  offset = 16;
                                }

                                offset = offset * 2;

                                // 130   2   0xBE 0x00              Temperature Sensor 1  0.1          °C
                                this->publish_state_(this->temperatures_[0].temperature_sensor_,
                                                    (float) ((int16_t) jk_get_16bit(130 + offset)) * 0.1f);

                                То есть, для получения температуры, мы должны стартовать со 130 байта + некий offset, который по
                                определению может быть либо 0 либо 32
                                */

                                int startByte = 130;
                                int offset = 0;
                                
                                int result = bd.getInt16(startByte + offset, Endian.little);
                                String roundedString = (result * 0.1).toStringAsFixed(2);
                                double roundedTemp = double.parse(roundedString);
                                print('temp: ${roundedTemp} °C');

                              } catch (e) {
                                null;
                              } 


                            });
                          });
                          // List<int> value = await characteristic.read();
                          // print('value: ${value.toString()}');
                        }
                      }
                    }
                  }
                  
                }, 
                child: Text('COMMAND_CELL_INFO')
              ),
            ],
          ),
        ),
      ),
    );
  }
}
