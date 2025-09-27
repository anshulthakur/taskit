import 'package:flutter/services.dart';

class CalendarChannel {
  static const MethodChannel _channel = MethodChannel('app.channel.calendar');

  static Future<bool> isPackageInstalled(String packageName) async {
    final result = await _channel.invokeMethod('isPackageInstalled', {'packageName': packageName});
    return result as bool;
  }

  static Future<bool> addEvent({
    required String title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
  }) async {
    final result = await _channel.invokeMethod('addGoogleCalendarEvent', {
      'title': title,
      'description': description,
      'startTime': startTime?.toUtc().millisecondsSinceEpoch ?? DateTime.now().toUtc().millisecondsSinceEpoch,
      'endTime': endTime?.toUtc().millisecondsSinceEpoch ?? DateTime.now().toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch,
    });
    return result == true;
  }
}
