import 'dart:async';

import 'package:flutter/services.dart';

/// Where the app was asked to open to, from outside it: the app icon's long-press menu, the Quick
/// Settings tile and the home-screen widget all send "quicklog". Nothing happens off Android.
class LaunchRoutes {
  LaunchRoutes([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('sj/launch');

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();
  bool _listening = false;

  /// Routes that arrive while the app is already open.
  Stream<String> get stream {
    if (!_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'route' && call.arguments is String) _controller.add(call.arguments as String);
      });
    }
    return _controller.stream;
  }

  /// The route the app was started with, if any (asked for once).
  Future<String?> initial() async {
    try {
      return await _channel.invokeMethod<String>('initialRoute');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
