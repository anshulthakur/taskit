
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/config': (context) => const ConfigScreen(),
      },
    );
  }
}

const MethodChannel _processTextChannel = MethodChannel('app.channel.process.data');
const MethodChannel _calendarChannel = MethodChannel('app.channel.calendar');

// List of available providers
final List<IntegrationProvider> _availableProviders = [GoogleCalendarProvider()];

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
  String get packageName;
  Future<void> createTask(String title, DateTime? dueDate, String? description, BuildContext context);
}

class GoogleCalendarProvider implements IntegrationProvider {
  @override
  String get name => 'Google Calendar';
  @override
  String get packageName => 'com.google.android.calendar';

  @override
  Future<void> createTask(String title, DateTime? dueDate, String? description, BuildContext context) async {
    if (kDebugMode) {
      print('Starting createTask: title=$title, dueDate=$dueDate');
    }

    try {
      final result = await _calendarChannel.invokeMethod('addGoogleCalendarEvent', {
        'title': title.isNotEmpty ? title : 'TaskIt Task',
        'description': description ?? 'Created by TaskIt',
        'startTime': dueDate?.toUtc().millisecondsSinceEpoch ?? DateTime.now().toUtc().millisecondsSinceEpoch,
        'endTime': (dueDate?.toUtc() ?? DateTime.now().toUtc()).add(const Duration(hours: 1)).millisecondsSinceEpoch,
      });

      if (result == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task created successfully')),
        );
      } else {
        if (kDebugMode) {
          print('Calendar intent failed or cancelled');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Failed to add task via intent: $e');
      }
      throw Exception('Failed to add task to calendar app: $e');
    }
  }

}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

//class _SplashScreenState extends State<SplashScreen> {
class _SplashScreenState extends State<SplashScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    //clearPreferredApp();
    _handleSharedText();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kDebugMode) {
      print('App lifecycle state changed: $state');
    }
  }

  Future<void> clearPreferredApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('preferred_app');
    if (kDebugMode) {
      print('Cleared preferred_app');
    }
  }

  Future<void> _handleSharedText() async {
    final text = await getSharedText();
    final prefs = await SharedPreferences.getInstance();
    final preferredApp = prefs.getString('preferred_app');

    if (!mounted) return;

    if (preferredApp == null) {
      Navigator.pushReplacementNamed(context, '/config');
      return;
    }

    if (text != null && text.isNotEmpty) {
      await _createTaskFromText(text);
    } else {
      Navigator.pushReplacementNamed(
        context,
        '/config',
        arguments: {'sharedText': text},
      );
    }
  }

  Future<void> _createTaskFromText(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final preferredApp = prefs.getString('preferred_app') ?? _availableProviders.first.packageName;
    final provider = _availableProviders.firstWhere(
      (p) => p.packageName == preferredApp,
      orElse: () => _availableProviders.first,
    );
    if (!mounted) return;
    await provider.createTask(text, DateTime.now(), null, context);
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/icons/app_icon.png', height: 100, width: 100),
            const SizedBox(height: 16),
            const Text('TaskIt', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String? _preferredApp;
  final List<IntegrationProvider> _providers = _availableProviders; // Use the global list

  String? _sharedText;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _sharedText = args?['sharedText'] as String?;
  }

  @override
  void initState() {
    super.initState();
    _loadPreferredApp();
  }

  Future<void> _loadPreferredApp() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _preferredApp = prefs.getString('preferred_app') ?? _providers.first.packageName;
    });
  }

  Future<void> _savePreferredApp(String app) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('preferred_app', app);
    if (kDebugMode) {
      print('Preferred app saved: $app');
    }

    if (!mounted) return;

    if (_sharedText != null && _sharedText!.isNotEmpty) {
      final provider = _providers.firstWhere((p) => p.packageName == app);
      await provider.createTask(_sharedText!, DateTime.now(), null, context);
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configure TaskIt')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Preferred Calendar App'),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 280,
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Select Provider',
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _preferredApp,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _preferredApp = value);
                      _savePreferredApp(value);
                    }
                  },
                  items: _providers.map((provider) {
                    return DropdownMenuItem<String>(
                      value: provider.packageName,
                      child: Text(provider.name),
                    );
                  }).toList(),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}