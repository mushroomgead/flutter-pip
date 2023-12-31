import 'package:flutter/material.dart';
import 'dart:core';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_application_1/services/flutter_whip.dart';
import 'package:flutter_application_1/services/webrtc_native.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_pip_mode/simple_pip.dart';

class WhipPublishSample extends StatefulWidget {
  static String tag = 'whip_publish_sample';

  @override
  _WhipPublishSampleState createState() => _WhipPublishSampleState();
}

class _WhipPublishSampleState extends State<WhipPublishSample>
    with WidgetsBindingObserver {
  MediaStream? _localStream;
  final _localRenderer = RTCVideoRenderer();
  String stateStr = 'init';
  bool _connecting = false;
  late WHIP _whip;

  TextEditingController _serverController = TextEditingController();
  late SharedPreferences _preferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isAndroid) {
      SimplePip().setAutoPipMode();
    }
    initRenderers();
    _loadSettings();
  }

  void _loadSettings() async {
    _preferences = await SharedPreferences.getInstance();
    this.setState(() {
      _serverController.text = _preferences.getString('pushserver') ??
          'https://demo.cloudwebrtc.com:8080/whip/publish/live/stream1';
    });
  }

  @override
  void deactivate() {
    super.deactivate();
    _localRenderer.dispose();
  }

  void _saveSettings() {
    _preferences.setString('pushserver', _serverController.text);
  }

  void initRenderers() async {
    await _localRenderer.initialize();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  void _connect() async {
    final url = _serverController.text;

    if (url.isEmpty) {
      return;
    }

    _saveSettings();

    _whip = WHIP(url: url);

    _whip.onState = (WhipState state) {
      setState(() {
        switch (state) {
          case WhipState.kNew:
            stateStr = 'New';
            break;
          case WhipState.kInitialized:
            stateStr = 'Initialized';
            break;
          case WhipState.kConnecting:
            stateStr = 'Connecting';
            break;
          case WhipState.kConnected:
            // Turn on pip mode
            if (Platform.isAndroid) {
              SimplePip().setAutoPipMode();
            } else if (Platform.isIOS) {
              _createPiP();
            }

            stateStr = 'Connected';
            break;
          case WhipState.kDisconnected:
            stateStr = 'Closed';
            break;
          case WhipState.kFailure:
            stateStr = 'Failure: ${_whip.lastError.toString()}';
            break;
        }
      });
    };

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'mandatory': {
          'minWidth': '1280',
          'minHeight': '720',
          'minFrameRate': '30',
        },
        'facingMode': 'user',
        'optional': [],
      }
    };

    try {
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localStream = stream;
      _localRenderer.srcObject = _localStream;
      await _whip.initlize(mode: WhipMode.kSend, stream: _localStream);
      await _whip.connect();
    } catch (e) {
      print('connect: error => ' + e.toString());
      _localRenderer.srcObject = null;
      _localStream?.dispose();
      return;
    }
    if (!mounted) return;

    setState(() {
      _connecting = true;
    });
  }

  void _disconnect() async {
    try {
      _disposePiP();
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localRenderer.srcObject = null;
      _whip.close();
      setState(() {
        _connecting = false;
      });
    } catch (e) {
      print(e.toString());
    }
  }

  void _toggleCamera() async {
    if (_localStream == null) throw Exception('Stream is not initialized');
    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');
    await Helper.switchCamera(videoTrack);
  }

  void _createPiP() {
    if (_localStream == null || _whip.pc == null) return;

    WebRTCNative().createPipVideoCall(
      remoteStreamId: _localStream!.id,
      peerConnectionId: _whip.pc!.peerConnectionId,
    );
  }

  void _disposePiP() {
    WebRTCNative().disposePiP();
  }

  bool visibleOption = true;

  @override
  void dispose() {
    // Remove the observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // These are the callbacks
    switch (state) {
      case AppLifecycleState.resumed:
        // widget is resumed
        break;
      case AppLifecycleState.inactive:
        // widget is inactive
        break;
      case AppLifecycleState.paused:
        if (Platform.isAndroid) {
          SimplePip().setAutoPipMode();
        }
        // widget is paused
        break;
      case AppLifecycleState.detached:
        // widget is detached
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        child: Stack(children: <Widget>[
          if (_connecting)
            Center(
              child: Container(
                margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                decoration: BoxDecoration(color: Colors.black54),
                child: RTCVideoView(_localRenderer,
                    mirror: true,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: Column(children: <Widget>[
              if (visibleOption)
                Padding(
                  padding: const EdgeInsets.only(top: 15.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              //exitScreen();
                              if (_connecting) {
                                _disconnect();
                              }
                              Navigator.pop(context);
                            },
                            icon: Icon(Icons.close,
                                color: Colors.black, size: 25.0),
                          ),
                          if (!_connecting)
                            IconButton(
                              icon: Icon(Icons.qr_code_scanner_sharp),
                              onPressed: () async {},
                            ),
                          if (_connecting)
                            IconButton(
                              icon: Icon(Icons.switch_video),
                              onPressed: _toggleCamera,
                            ),
                          Row(
                            children: [
                              Platform.isAndroid
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () {
                                        SimplePip(onPipEntered: () {
                                          setState(() {
                                            visibleOption = false;
                                            debugPrint(
                                                "SimplePip:: onPipEntered");
                                          });
                                        }, onPipExited: () {
                                          setState(() {
                                            visibleOption = true;
                                            debugPrint(
                                                "SimplePip:: onPipExited");
                                          });
                                        }).enterPipMode(
                                            aspectRatio: [16, 9],
                                            seamlessResize: true);
                                      },
                                      icon: Icon(
                                          Icons.picture_in_picture_alt_outlined,
                                          color: Colors.black,
                                          size: 25.0),
                                    )
                                  : SizedBox(),
                            ],
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              FittedBox(
                child: Text(
                  '${stateStr}',
                  textAlign: TextAlign.left,
                ),
              ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 18.0, 10.0, 0),
                  child: Align(
                    child: Text('WHIP URI:'),
                    alignment: Alignment.centerLeft,
                  ),
                ),
              if (!_connecting)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10.0, 0.0, 10.0, 0),
                  child: TextFormField(
                    controller: _serverController,
                    keyboardType: TextInputType.text,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      contentPadding: EdgeInsets.all(10.0),
                      border: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black12)),
                    ),
                  ),
                )
            ]),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _connecting ? _disconnect : _connect,
        tooltip: _connecting ? 'Hangup' : 'Call',
        backgroundColor: null,
        mini: true,
        child: Icon(_connecting ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
