import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart'; // Updated import
import 'package:http/http.dart' as http;
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

// Google Calendar Provider with API and intent fallback
class GoogleCalendarProvider implements IntegrationProvider {
  @override
  String get name => 'Google Calendar';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/calendar.events'],
  );

  Future<calendar.CalendarApi?> _getCalendarApi() async {
    try {
      // Attempt silent sign-in, fall back to interactive
      final account = await _googleSignIn.signInSilently() ?? await _googleSignIn.signIn();
      if (account == null) {
        if (kDebugMode) {
          print('Google Sign-In failed: No account selected');
        }
        return null;
      }

      // Get auth headers (includes access token)
      final headers = await account.authHeaders;
      final accessToken = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (accessToken == null) {
        if (kDebugMode) {
          print('Google Sign-In failed: No access token');
        }
        return null;
      }

      // Create authenticated client
      final credentials = AccessCredentials(
        AccessToken('Bearer', accessToken, DateTime.now().add(const Duration(hours: 1))),
        null, // Refresh token (not needed for short-lived access)
        ['https://www.googleapis.com/auth/calendar.events'],
      );
      final client = authenticatedClient(http.Client(), credentials);
      return calendar.CalendarApi(client);
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In error: $e');
      }
      return null;
    }
  }

  @override
  Future<void> createTask(String title, DateTime? dueDate, String? description) async {
    // Request calendar permissions for intent-based approach
    final status = await Permission.calendarWriteOnly.request();
    if (!status.isGranted) {
      throw Exception('Calendar write permission denied. Please enable in settings.');
    }

    final event = calendar.Event(
      summary: title.isNotEmpty ? title : 'TaskIt Event',
      description: description ?? 'Created by TaskIt',
      start: calendar.EventDateTime(dateTime: dueDate ?? DateTime.now()),
      end: calendar.EventDateTime(dateTime: (dueDate ?? DateTime.now()).add(const Duration(hours: 1))),
    );

    if (kDebugMode) {
      print('Creating event: summary=${event.summary}, start=${event.start?.dateTime}, '
            'end=${event.end?.dateTime}, desc=${event.description}');
    }

    // Try Google Calendar API first
    final api = await _getCalendarApi();
    if (api != null) {
      try {
        await api.events.insert(event, 'primary');
        if (kDebugMode) {
          print('Event created successfully via Google Calendar API');
        }
        return; // Success, no fallback needed
      } catch (e) {
        if (kDebugMode) {
          print('Calendar API error: $e');
        }
        // Fall through to intent-based approach
      }
    } else {
      if (kDebugMode) {
        print('Calendar API unavailable, falling back to intent');
      }
    }

    // Fallback to intent-based approach
    try {
      final intentEvent = Event(
        title: event.summary!,
        description: event.description ?? '',
        startDate: event.start!.dateTime!,
        endDate: event.end!.dateTime!,
      );
      bool success = await Add2Calendar.addEvent2Cal(intentEvent);
      if (kDebugMode) {
        print('addEvent2Cal result: $success');
      }
      if (success) {
        return; // Success with add_2_calendar
      }
      if (kDebugMode) {
        print('addEvent2Cal failed, trying custom intent');
      }

      await _calendarChannel.invokeMethod('addCalendarEvent', {
        'title': event.summary,
        'description': event.description,
        'startTime': event.start!.dateTime!.millisecondsSinceEpoch,
        'endTime': event.end!.dateTime!.millisecondsSinceEpoch,
      });
      if (kDebugMode) {
        print('Custom calendar intent dispatched successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Intent-based error: $e');
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