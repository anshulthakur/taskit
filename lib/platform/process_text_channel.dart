import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class ProcessTextChannel {
  static const MethodChannel _channel = MethodChannel('app.channel.process.data');

  static Future<String?> getSharedText() async {
    try {
      final sharedData = await _channel.invokeMethod('getSharedText');
      if (sharedData is String) {
        if (kDebugMode) {
          print('Shared text retrieved: $sharedData');
        }
        return sharedData;
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error retrieving shared text: $e');
      }
      return null;
    }
  }
}
