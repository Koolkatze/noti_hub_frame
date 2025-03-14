import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_notification_listener/flutter_notification_listener.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:simple_frame_app/text_utils.dart';
import 'package:simple_frame_app/simple_frame_app.dart';
import 'package:simple_frame_app/tx/sprite.dart';
import 'package:simple_frame_app/tx/plain_text.dart';

void main() => runApp(const MainApp());

final _log = Logger("MainApp");

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => MainAppState();
}

/// SimpleFrameAppState mixin helps to manage the lifecycle of the Frame connection outside of this file
class MainAppState extends State<MainApp> with SimpleFrameAppState {
  ReceivePort port = ReceivePort();
  String _prevText = '';
  Uint8List _prevIcon = Uint8List(0);
  NotificationEvent? _lastEvent;
  final TextStyle _style = const TextStyle(color: Colors.white, fontSize: 18);
  final TextStyle _smallStyle =
      const TextStyle(color: Colors.white, fontSize: 12);

  MainAppState() {
    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen((record) {
      debugPrint(
          '${record.level.name}: [${record.loggerName}] ${record.time}: ${record.message}');
    });
  }

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // we must use static method, to handle in background
  // prevent dart from stripping out this function on release build in Flutter 3.x
  @pragma('vm:entry-point')
  static void _callback(NotificationEvent evt) {
    _log.fine("send evt to ui: $evt");
    final SendPort? send = IsolateNameServer.lookupPortByName("_listener_");
    if (send == null) _log.severe("can't find the sender");
    send?.send(evt);
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    setState(() {
      ApplicationState.initializing;
    });

    _log.info('Initializing platform state');
    NotificationsListener.initialize(callbackHandle: _callback);

    // this can fix restart<debug> can't handle error
    IsolateNameServer.removePortNameMapping("_listener_");
    IsolateNameServer.registerPortWithName(port.sendPort, "_listener_");
    port.listen((message) => handleNotification(message));

    var isRunning = (await NotificationsListener.isRunning) ?? false;
    _log.info('Service is already running: $isRunning');

    setState(() {
      ApplicationState.ready;
    });
  }

  /// Extract the details from the notification and send to Frame
  void handleNotification(NotificationEvent event) async {
    _log.fine('onData: $event');

    // filter notifications for EVERYTHING ALLOWED
    if (event.packageName != null) {
      setState(() {
        _lastEvent = event;
      });

      try {
        // send text to Frame
        String text = '${event.title}\n${event.text}\n${event.raw!["subText"]}';
        if (text != _prevText) {
          String wrappedText = TextUtils.wrapText(text, 500, 4);
          await frame
              ?.sendMessage(TxPlainText(msgCode: 0x0a, text: wrappedText));
          _prevText = text;
        }

        if (event.hasLargeIcon!) {
          Uint8List iconBytes = event.largeIcon!;
          _log.finest('Icon bytes: ${iconBytes.length}: $iconBytes');

          if (!listEquals(iconBytes, _prevIcon)) {
            _prevIcon = iconBytes;
            // TODO if the maps icons are all 2-color bitmaps even though they're RGB(A?) bitmaps,
            // maybe we can pack them and send as an indexed file more easily than having to do quantize()? Or using Image() at all.
            final img.Image? image = img.decodeImage(iconBytes);

            // Ensure the image is loaded correctly
            if (image != null) {
              _log.fine(
                  'Image: ${image.width}x${image.height}, ${image.format}, ${image.hasAlpha}, ${image.hasPalette}, ${image.length}');
              _log.finest('Image bytes: ${image.toUint8List()}');

              // quantize the image for pack/send/display to frame
              final qImage = img.quantize(image,
                  numberOfColors: 4,
                  method: img.QuantizeMethod.binary,
                  dither: img.DitherKernel.none,
                  ditherSerpentine: false);
              Uint8List qImageBytes = qImage.toUint8List();
              _log.fine(
                  'QuantizedImage: ${qImage.width}x${qImage.height}, ${qImage.format}, ${qImage.hasAlpha}, ${qImage.hasPalette}, ${qImage.palette!.toUint8List()}, ${qImage.length}');
              _log.finest('QuantizedImage bytes: $qImageBytes');

              // send image message (header and image data) to Frame
              await frame?.sendMessage(TxSprite(
                  msgCode: 0x0d,
                  width: qImage.width,
                  height: qImage.height,
                  numColors: qImage.palette!.lengthInBytes ~/ 3,
                  paletteData: qImage.palette!.toUint8List(),
                  pixelData: qImageBytes));
            }
          }
        }
      } catch (e) {
        _log.severe('Error processing notification: $e');
      }
    }
  }

  @override
  Future<void> run() async {
    _log.info("start listening");

    var hasPermission = (await NotificationsListener.hasPermission)!;
    _log.info("permission: $hasPermission");

    if (!hasPermission) {
      _log.info("no permission, so open settings");
      NotificationsListener.openPermissionSettings();
    } else {
      _log.info("has permission, so open settings anyway");
      // TODO seems not to update hasPermission to false after stopService
      // TODO Occasionally the permission disappears from both approved and denied lists in the UI...?
      // so force an openPermissionSettings on startListening every time
      NotificationsListener.openPermissionSettings();
    }

    var isRunning = (await NotificationsListener.isRunning)!;
    _log.info("running: $isRunning");

    if (!isRunning) {
      _log.info("not running: starting service");
      await NotificationsListener.startService(foreground: false);
    }

    setState(() {
      currentState = ApplicationState.running;
    });
  }

  @override
  Future<void> cancel() async {
    _log.info("stop listening");

    setState(() {
      currentState = ApplicationState.stopping;
    });

    bool stopped = (await NotificationsListener.stopService())!;
    _log.info("service stopped: $stopped");

    setState(() {
      _prevText = '';
      _prevIcon = Uint8List(0);
      _lastEvent = null;
      currentState = ApplicationState.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'frame Notification HUB',
        theme: ThemeData.dark(),
        home: Scaffold(
          appBar: AppBar(
              title: const Text('frame Notification HUB'),
              actions: [getBatteryWidget()]),
          body: _lastEvent != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _lastEvent!.title ?? "",
                              style: _style,
                              textAlign: TextAlign.left,
                            ),
                            Text(_lastEvent!.text ?? "", style: _style),
                            Text(_lastEvent!.raw!["subText"] ?? "",
                                style: _style),
                            // phone only - last notification timestamp
                            Text(
                                _lastEvent!.createAt
                                    .toString()
                                    .substring(0, 19),
                                style: _smallStyle),
                          ]),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        if (_lastEvent!.hasLargeIcon!)
                          Image.memory(_lastEvent!.largeIcon!),
                      ],
                    )
                  ],
                )
              : null,
          floatingActionButton: getFloatingActionButtonWidget(
              const Icon(Icons.navigation), const Icon(Icons.cancel)),
          persistentFooterButtons: getFooterButtonsWidget(),
        ));
  }
}
