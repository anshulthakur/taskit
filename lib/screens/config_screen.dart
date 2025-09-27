import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/provider_registry.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  String? _preferredApp;
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
      _preferredApp = prefs.getString('preferred_app') ?? availableProviders.first.packageName;
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
      final provider = availableProviders.firstWhere((p) => p.packageName == app);
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
                  items: availableProviders.map((provider) {
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
