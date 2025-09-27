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
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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
  try {
    final sharedData = await _processTextChannel.invokeMethod('getSharedText');
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

Future<bool> isPackageInstalled(String packageName) async {
  try {
    final result = await _calendarChannel.invokeMethod('isPackageInstalled', {'packageName': packageName});
    if (kDebugMode) {
      print('Package $packageName installed: $result');
    }
    return result as bool;
  } catch (e) {
    if (kDebugMode) {
      print('Error checking package $packageName: $e');
    }
    return false;
  }
}

abstract class IntegrationProvider {
  String get name;
  Future<void> createTask(String title, DateTime? dueDate, String? description, bool isGoogleCalInstalled, BuildContext context);
}

class GoogleCalendarProvider implements IntegrationProvider {
  @override
  String get name => 'Google Calendar';
  static const String _serverClientId = '87427269367-3tr6mlp9khafuc7qedf8gi20tuut2gda.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const List<String> _calendarScopes = [
    'https://www.googleapis.com/auth/calendar.events',
  ];

  GoogleSignInAccount? _currentUser;
  bool _isInitialized = false;

  GoogleCalendarProvider() {
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(
        clientId: null,
        serverClientId: _serverClientId,
      );
      _googleSignIn.authenticationEvents
          .listen(_handleAuthEvent)
          .onError(_handleAuthError);
      _isInitialized = true;
      if (kDebugMode) {
        print('GoogleSignIn initialized successfully with clientId: $_serverClientId');
      }
    } catch (e) {
      _isInitialized = false;
      if (kDebugMode) {
        print('GoogleSignIn initialization error: $e');
      }
    }
  }

  Future<void> _handleAuthEvent(GoogleSignInAuthenticationEvent event) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _currentUser = event.user;
        if (kDebugMode) {
          print('GoogleSignIn: User signed in: ${_currentUser?.email}');
        }
      case GoogleSignInAuthenticationEventSignOut():
        _currentUser = null;
        if (kDebugMode) {
          print('GoogleSignIn: User signed out');
        }
    }
  }

  Future<void> _handleAuthError(Object e) async {
    _currentUser = null;
    if (kDebugMode) {
      print('Google Sign-In error: $e');
    }
  }

  Future<calendar.CalendarApi?> _getCalendarApi(BuildContext context) async {
    try {
      if (!_isInitialized) {
        if (kDebugMode) {
          print('GoogleSignIn not initialized, retrying...');
        }
        await _initializeGoogleSignIn();
      }

      if (_currentUser == null) {
        if (_googleSignIn.supportsAuthenticate()) {
          if (kDebugMode) {
            print('Attempting GoogleSignIn authentication');
          }
          await WidgetsBinding.instance.endOfFrame;
          _currentUser = await _googleSignIn.authenticate();
          if (_currentUser == null) {
            if (kDebugMode) {
              print('Authentication failed: No account selected or user cancelled');
            }
            bool retry = false;
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Authentication Required'),
                content: const Text('Please sign in with your Google account or ensure a Google account is configured on your device.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ).then((value) => retry = value ?? false);
            if (retry) {
              if (kDebugMode) {
                print('Retrying GoogleSignIn authentication');
              }
              await WidgetsBinding.instance.endOfFrame;
              _currentUser = await _googleSignIn.authenticate();
              if (_currentUser == null) {
                if (kDebugMode) {
                  print('Authentication failed again: No account selected or user cancelled');
                }
                return null;
              }
            } else {
              return null;
            }
          }
          if (kDebugMode) {
            print('Authentication successful: ${_currentUser?.email}');
          }
        } else {
          if (kDebugMode) {
            print('Platform does not support explicit authenticate()');
          }
          throw Exception('Platform does not support explicit authenticate()');
        }
      }

      if (kDebugMode) {
        print('Requesting authorization for scopes: $_calendarScopes');
      }
      var authorization = await _currentUser!.authorizationClient
          .authorizationForScopes(_calendarScopes);

      if (authorization == null) {
        if (kDebugMode) {
          print('No existing authorization, requesting scopes');
        }
        authorization = await _currentUser!.authorizationClient
            .authorizeScopes(_calendarScopes);
      }

      final headers = await _currentUser!.authorizationClient
          .authorizationHeaders(_calendarScopes);
      if (headers == null || !headers.containsKey('Authorization')) {
        if (kDebugMode) {
          print('No access token available');
        }
        return null;
      }

      final client = http.Client();
      final authedClient = authenticatedClient(
        client,
        AccessCredentials(
          AccessToken(
            'Bearer',
            headers['Authorization']!.split(' ').last,
            DateTime.now().toUtc().add(const Duration(hours: 1)),
          ),
          null,
          _calendarScopes,
        ),
      );

      if (kDebugMode) {
        print('Calendar API client created successfully');
      }
      return calendar.CalendarApi(authedClient);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        if (kDebugMode) {
          print('Sign-in canceled by user: $e');
        }
      } else {
        if (kDebugMode) {
          print('Google Sign-In configuration error: $e');
        }
        throw Exception(
          'Google Sign-In configuration error. Verify SHA-1 fingerprint, package name (me.bhaad.taskit), and client ID in Google Cloud Console.',
        );
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In error: $e');
      }
      return null;
    }
  }

  @override
  Future<void> createTask(
      String title, DateTime? dueDate, String? description, bool isGoogleCalInstalled, BuildContext context) async {
    if (kDebugMode) {
      print('Starting createTask: title=$title, dueDate=$dueDate, isGoogleCalInstalled=$isGoogleCalInstalled');
    }

    final api = await _getCalendarApi(context);
    if (api != null) {
      try {
        final status = await Permission.calendarWriteOnly.request();
        if (!status.isGranted) {
          if (kDebugMode) {
            print('Calendar write permission denied');
          }
          throw Exception('Calendar write permission denied.');
        }

        final event = calendar.Event(
          summary: title.isNotEmpty ? title : 'TaskIt Task',
          description: description ?? 'Created by TaskIt',
          start: calendar.EventDateTime(
            dateTime: dueDate?.toUtc() ?? DateTime.now().toUtc(),
          ),
          end: calendar.EventDateTime(
            dateTime: (dueDate?.toUtc() ?? DateTime.now().toUtc())
                .add(const Duration(hours: 1)),
          ),
        );

        await api.events.insert(event, 'primary');
        if (kDebugMode) {
          print('Task created via Google Calendar API');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          print('Calendar API error: $e');
        }
      }
    } else {
      if (kDebugMode) {
        print('Failed to initialize Calendar API, falling back to intent');
      }
    }

    try {
      if (isGoogleCalInstalled) {
        final result = await _calendarChannel.invokeMethod('addGoogleCalendarEvent', {
          'title': title.isNotEmpty ? title : 'TaskIt Task',
          'description': description ?? 'Created by TaskIt',
          'startTime': (dueDate?.toUtc() ?? DateTime.now().toUtc()).millisecondsSinceEpoch,
          'endTime': (dueDate?.toUtc() ?? DateTime.now().toUtc())
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch,
        });
        if (result == true) {
          if (kDebugMode) {
            print('Task added via direct Google Calendar intent');
          }
          return;
        } else {
          if (kDebugMode) {
            print('Direct Google Calendar intent failed, falling back to Add2Calendar');
          }
        }
      } else {
        if (kDebugMode) {
          print('Google Calendar not installed, skipping direct intent');
        }
      }

      final event = Event(
        title: title.isNotEmpty ? title : 'TaskIt Task',
        description: description ?? 'Created by TaskIt',
        startDate: dueDate?.toUtc() ?? DateTime.now().toUtc(),
        endDate: (dueDate?.toUtc() ?? DateTime.now().toUtc()).add(const Duration(hours: 1)),
      );
      final added = await Add2Calendar.addEvent2Cal(event);
      if (added) {
        if (kDebugMode) {
          print('Task added via Add2Calendar');
        }
        return;
      } else {
        if (kDebugMode) {
          print('Add2Calendar failed: No calendar app available');
        }
        throw Exception('No calendar app available to handle the task. Please ensure a calendar app like Google Calendar is installed and configured.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to add task to calendar: $e');
      }
      throw Exception('Failed to add task to calendar: $e');
    }
  }
}

class HomeScreen extends StatefulWidget {
  final List<IntegrationProvider>? providers;

  const HomeScreen({super.key, this.providers});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedText = '';
  String _title = '';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _description;
  IntegrationProvider? _selectedProvider;
  final List<IntegrationProvider> _providers = [];
  bool _providersLoaded = false;
  bool _isGoogleCalInstalled = false;

  late StreamSubscription _intentDataStreamSubscription;

  @override
  void initState() {
    super.initState();
    _loadProviders();
    _loadSharedText();
    _intentDataStreamSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      for (var file in value) {
        if (file.type == SharedMediaType.text) {
          final sharedText = file.path;
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

    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      for (var file in value) {
        if (file.type == SharedMediaType.text) {
          final sharedText = file.path;
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
      ReceiveSharingIntent.instance.reset();
    });
  }

  Future<void> _loadProviders() async {
    _isGoogleCalInstalled = await isPackageInstalled('com.google.android.calendar');
    if (widget.providers != null) {
      _providers.addAll(widget.providers!);
    } else {
      _providers.add(GoogleCalendarProvider());
    }

    await _loadSelectedProvider();
    setState(() => _providersLoaded = true);
  }

  Future<void> _loadSelectedProvider() async {
    final prefs = await SharedPreferences.getInstance();
    final savedName = prefs.getString('selected_provider');
    IntegrationProvider defaultProvider = _providers.first;
    if (savedName != null) {
      final provider = _providers.firstWhere(
        (p) => p.name == savedName,
        orElse: () => defaultProvider,
      );
      setState(() => _selectedProvider = provider);
    } else {
      setState(() => _selectedProvider = defaultProvider);
      await prefs.setString('selected_provider', defaultProvider.name);
    }
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

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _createTask() async {
    if (_selectedProvider == null || _title.isEmpty) {
      if (kDebugMode) {
        print('Cannot create task: provider=${_selectedProvider?.name}, title=$_title');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a provider and enter a title')),
      );
      return;
    }
    final dueDate = _selectedDate != null && _selectedTime != null
        ? DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            _selectedTime!.hour,
            _selectedTime!.minute,
          )
        : null;
    try {
      await _selectedProvider!.createTask(_title, dueDate, _description, _isGoogleCalInstalled, context);
      if (kDebugMode) {
        print('Task created successfully: title=$_title');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task created successfully')),
      );
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating task: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_providersLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/icons/app_icon.png',
              height: 24,
              width: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'TaskIt',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedText.isNotEmpty)
                Text(
                  'Selected/Shared Text: $_selectedText',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE0E0E0), thickness: 1),
              TextField(
                decoration: const InputDecoration(labelText: 'Title'),
                onChanged: (value) => setState(() => _title = value),
                controller: TextEditingController(text: _title),
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE0E0E0), thickness: 1),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Date'),
                        child: Text(
                          _selectedDate != null
                              ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
                              : 'Not set',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _selectTime,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Time'),
                        child: Text(
                          _selectedTime != null
                              ? _selectedTime!.format(context)
                              : 'Not set',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE0E0E0), thickness: 1),
              Center(
                child: SizedBox(
                  width: double.infinity, // Makes it span full width inside parent
                  child: DropdownButtonFormField<IntegrationProvider>(
                    decoration: const InputDecoration(
                      labelText: 'Select Provider',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: _selectedProvider,
                    onChanged: (provider) async {
                      if (provider != null) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('selected_provider', provider.name);
                        if (kDebugMode) {
                          print('Selected provider: ${provider.name}');
                        }
                        setState(() => _selectedProvider = provider);
                      }
                    },
                    items: _providers.map((provider) {
                      return DropdownMenuItem(
                        value: provider,
                        child: Text(provider.name),
                      );
                    }).toList(),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE0E0E0), thickness: 1),
              TextField(
                decoration: const InputDecoration(labelText: 'Task Details (optional)'),
                onChanged: (value) => setState(() => _description = value),
                controller: TextEditingController(text: _description),
                maxLines: 5,
                keyboardType: TextInputType.multiline,
              ),
              const SizedBox(height: 32),
              Center(
                child: SizedBox(
                  width: 240, // Adjust width as needed
                  child: ElevatedButton(
                    onPressed: _createTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Create Task'),
                  ),
                ),
              ),

              const SizedBox(height: 24), // Optional bottom spacing
            ],
          ),
        ),
      ),
    );
  }
}