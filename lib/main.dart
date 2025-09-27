import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/config_screen.dart';

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
