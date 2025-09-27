import 'package:flutter/material.dart';

abstract class IntegrationProvider {
  String get name;
  String get packageName;
  Future<void> createTask(String title, DateTime? dueDate, String? description, BuildContext context);
}
