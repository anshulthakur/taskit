import 'package:flutter/material.dart';
import '../platform/calendar_channel.dart';
import 'integration_provider.dart';

class GoogleCalendarProvider implements IntegrationProvider {
  @override
  String get name => 'Google Calendar';

  @override
  String get packageName => 'com.google.android.calendar';

  @override
  Future<void> createTask(String title, DateTime? dueDate, String? description, BuildContext context) async {
    final result = await CalendarChannel.addEvent(
      title: title,
      description: description,
      startTime: dueDate,
      endTime: dueDate?.add(const Duration(hours: 1)),
    );

    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created successfully')),
      );
    }
  }
}
