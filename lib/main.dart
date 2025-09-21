import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/tasks/v1.dart' as tasks;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const TaskitApp());
}

class TaskitApp extends StatelessWidget {
  const TaskitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TaskIt',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

const MethodChannel _processTextChannel = MethodChannel('app.channel.process.data');
const MethodChannel _calendarChannel = MethodChannel('app.channel.calendar');

Future<String?> getSharedText() async {
  final sharedData = await _processTextChannel.invokeMethod('getSharedText');
  if (sharedData is String) {
    return sharedData;
  }
  return null;
}

// Abstract provider for extensibility
abstract class IntegrationProvider {
  String get name;
  Future<void> createTask(String title, DateTime? dueDate, String? description);
}

// Google Calendar Provider with fallback to custom intent
class GoogleCalendarProvider implements IntegrationProvider {
  @override
  String get name => 'Google Calendar';

  @override
  Future<void> createTask(String title, DateTime? dueDate, String? description) async {
    // Request calendar permissions
    final status = await Permission.calendarWriteOnly.request();
    if (!status.isGranted) {
      throw Exception('Calendar write permission denied. Please enable in settings.');
    }

    final Event event = Event(
      title: title.isNotEmpty ? title : 'TaskIt Event',
      description: description ?? 'Created by TaskIt',
      startDate: dueDate ?? DateTime.now(),
      endDate: (dueDate ?? DateTime.now()).add(const Duration(hours: 1)),
    );

    if (kDebugMode) {
      print('Creating event: title=${event.title}, start=${event.startDate}, '
            'end=${event.endDate}, desc=${event.description}');
    }

    // Try add_2_calendar first
    try {
      bool success = await Add2Calendar.addEvent2Cal(event);
      if (kDebugMode) {
        print('addEvent2Cal result: $success');
      }
      if (success) {
        return; // Success, no need for fallback
      }
      if (kDebugMode) {
        print('addEvent2Cal failed, falling back to custom intent');
      }
    } catch (e) {
      if (kDebugMode) {
        print('addEvent2Cal error: $e');
      }
    }

    // Fallback to custom intent
    try {
      await _calendarChannel.invokeMethod('addCalendarEvent', {
        'title': event.title,
        'description': event.description,
        'startTime': event.startDate.millisecondsSinceEpoch,
        'endTime': event.endDate.millisecondsSinceEpoch,
      });
      if (kDebugMode) {
        print('Custom calendar intent dispatched successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Custom calendar intent error: $e');
      }
      throw Exception('Failed to add event to Google Calendar: $e');
    }
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedText = '';
  String _title = '';
  DateTime? _dueDate;
  String? _description;
  IntegrationProvider? _selectedProvider;
  final List<IntegrationProvider> _providers = [
    GoogleCalendarProvider(),
    // Add more providers here
  ];

  @override
  void initState() {
    super.initState();
    _loadSharedText();
  }

  Future<void> _loadSharedText() async {
    final text = await getSharedText();
    if (text != null && text.isNotEmpty) {
      setState(() {
        _selectedText = text;
        _title = text;
        _description = text;
      });
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dueDate ?? DateTime.now()),
      );
      if (time != null) {
        setState(() {
          _dueDate = DateTime(
            picked.year,
            picked.month,
            picked.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _createTask() async {
    if (_selectedProvider == null || _title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a provider and enter a title')),
      );
      return;
    }
    try {
      await _selectedProvider!.createTask(_title, _dueDate, _description);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task/Event created successfully')),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TaskIt')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_selectedText.isNotEmpty)
              Text(
                'Selected Text: $_selectedText',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (value) => _title = value,
              controller: TextEditingController(text: _title),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              onChanged: (value) => _description = value,
              controller: TextEditingController(text: _description),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Due Date: '),
                Text(
                  _dueDate != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(_dueDate!)
                      : 'Not set',
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: () => _selectDate(context),
                  child: const Text('Select Date/Time'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButton<IntegrationProvider>(
              hint: const Text('Select Provider'),
              value: _selectedProvider,
              onChanged: (provider) => setState(() => _selectedProvider = provider),
              items: _providers.map((provider) {
                return DropdownMenuItem(
                  value: provider,
                  child: Text(provider.name),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _createTask,
              child: const Text('Create Task/Event'),
            ),
          ],
        ),
      ),
    );
  }
}