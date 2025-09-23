import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/googleapis_auth.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';  // For share intents
import 'dart:async';  // For StreamSubscription

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
    clientId: null, // Not needed for Android with correct SHA-1
  );

  Future<calendar.CalendarApi?> _getCalendarApi() async {
    try {
      // Try silent sign-in first
      var account = await _googleSignIn.signInSilently();
      if (account == null) {
        if (kDebugMode) {
          print('Silent sign-in failed, attempting interactive sign-in');
        }
        account = await _googleSignIn.signIn();
      }
      if (account == null) {
        if (kDebugMode) {
          print('Google Sign-In failed: No account selected');
        }
        return null;
      }
      if (kDebugMode) {
        print('Google Sign-In succeeded: Account=${account.email}');
      }

      // Request Calendar API scope
      final granted = await _googleSignIn.requestScopes(['https://www.googleapis.com/auth/calendar.events']);
      if (!granted) {
        if (kDebugMode) {
          print('Google Sign-In failed: Calendar scope not granted');
        }
        return null;
      }
      if (kDebugMode) {
        print('Calendar scope granted successfully');
      }

      // Get auth headers
      final headers = await account.authHeaders;
      final accessToken = headers['Authorization']?.replaceFirst('Bearer ', '');
      if (accessToken == null) {
        if (kDebugMode) {
          print('Google Sign-In failed: No access token');
        }
        return null;
      }
      if (kDebugMode) {
        print('Access token obtained successfully');
      }

      // Create authenticated client
      final credentials = AccessCredentials(
        AccessToken(
          'Bearer',
          accessToken,
          DateTime.now().toUtc().add(const Duration(hours: 1)), // Use UTC
        ),
        null, // Refresh token not needed
        ['https://www.googleapis.com/auth/calendar.events'],
      );
      final client = authenticatedClient(http.Client(), credentials);
      if (kDebugMode) {
        print('Authenticated client created successfully');
      }
      return calendar.CalendarApi(client);
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In error: $e');
      }
      if (e.toString().contains('ApiException: 10')) {
        throw Exception('Google Sign-In configuration error. Check SHA-1 and package name in Google Cloud Console.');
      } else if (e.toString().contains('expiry')) {
        throw Exception('Invalid DateTime format for access token expiry. Contact developer.');
      }
      return null;
    }
  }

  @override
  Future<void> createTask(String title, DateTime? dueDate, String? description) async {
    if (kDebugMode) {
      print('Starting createTask: title=$title, dueDate=$dueDate, description=$description');
    }

    // Request calendar permissions for intent-based approach
    final status = await Permission.calendarWriteOnly.request();
    if (!status.isGranted) {
      if (kDebugMode) {
        print('Calendar write permission denied');
      }
      throw Exception('Calendar write permission denied. Please enable in settings.');
    }
    if (kDebugMode) {
      print('Calendar write permission granted');
    }

    final event = calendar.Event(
      summary: title.isNotEmpty ? title : 'TaskIt Event',
      description: description ?? 'Created by TaskIt',
      start: calendar.EventDateTime(dateTime: dueDate?.toUtc() ?? DateTime.now().toUtc()),
      end: calendar.EventDateTime(dateTime: (dueDate?.toUtc() ?? DateTime.now().toUtc()).add(const Duration(hours: 1))),
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
        throw Exception('Failed to create event via API: $e');
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
        if (kDebugMode) {
          print('Event added successfully via add_2_calendar');
        }
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

  late StreamSubscription _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadSharedText();
    // Listen for share intents (e.g., from WhatsApp)
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      for (var file in value) {
        if (file.type == SharedMediaType.text) {
          final sharedText = file.path;  // Text content is in 'path' for SharedMediaType.text
          if (sharedText.isNotEmpty) {
            if (kDebugMode) {
              print('Shared text received: $sharedText');
            }
            setState(() {
              _selectedText = sharedText;
              _title = sharedText;
              _description = sharedText;
            });
            break;
          }
        }
      }
    }, onError: (err) {
      if (kDebugMode) {
        print('getMediaStream error: $err');
      }
    });

    // Handle share intents when app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      for (var file in value) {
        if (file.type == SharedMediaType.text) {
          final sharedText = file.path;  // Text content is in 'path' for SharedMediaType.text
          if (sharedText.isNotEmpty) {
            if (kDebugMode) {
              print('Initial shared text: $sharedText');
            }
            setState(() {
              _selectedText = sharedText;
              _title = sharedText;
              _description = sharedText;
            });
            break;
          }
        }
      }
      // Tell the library we are done processing the initial intent
      ReceiveSharingIntent.instance.reset();
    });
  }

  @override
  void dispose() {
    _intentDataStreamSubscription.cancel();
    super.dispose();
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
                'Selected/Shared Text: $_selectedText',
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