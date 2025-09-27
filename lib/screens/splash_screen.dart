import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/provider_registry.dart';
import '../platform/process_text_channel.dart';


class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _handleSharedText() async {
    final text = await ProcessTextChannel.getSharedText();
    final prefs = await SharedPreferences.getInstance();
    final preferredApp = prefs.getString('preferred_app');

    if (!mounted) return;

    if (text != null && text.isNotEmpty) {
      if (preferredApp == null) {
        Navigator.pushReplacementNamed(
          context,
          '/config',
          arguments: {'sharedText': text},
        );
      } else {
        await _createTaskFromText(text);
      }
    } else {
      Navigator.pushReplacementNamed(context, '/config');
    }
  }

  Future<void> _createTaskFromText(String text) async {
    final prefs = await SharedPreferences.getInstance();
    final preferredApp = prefs.getString('preferred_app') ?? availableProviders.first.packageName;
    final provider = availableProviders.firstWhere(
      (p) => p.packageName == preferredApp,
      orElse: () => availableProviders.first,
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
