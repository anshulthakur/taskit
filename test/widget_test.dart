
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskit/main.dart';

import 'widget_test.mocks.dart';

@GenerateMocks([IntegrationProvider])
void main() {
  group('Widget Tests', () {
    late MockIntegrationProvider mockProvider;

    setUp(() {
      mockProvider = MockIntegrationProvider();
      when(mockProvider.name).thenReturn('Mock Provider');
    });

    testWidgets('HomeScreen shows loading indicator and then main UI',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues(
          {'selected_provider': 'Mock Provider'});

      // Act
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          providers: [mockProvider],
        ),
      ));

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Act
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('TaskIt'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsNWidgets(2));
    });

    testWidgets('Create Task button calls provider and shows snackbar on success',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues(
          {'selected_provider': 'Mock Provider'});
      when(mockProvider.createTask(any, any, any, any, any))
          .thenAnswer((_) async {});

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          providers: [mockProvider],
        ),
      ));
      await tester.pumpAndSettle();

      // Set a title to enable the create button
      await tester.enterText(find.byType(TextField).first, 'Test Title');
      await tester.pump();

      // Act
      await tester.tap(find.text('Create Task/Event'));
      await tester.pumpAndSettle();

      // Assert
      verify(mockProvider.createTask(
        'Test Title',
        null,
        '',
        any,
        any,
      )).called(1);
      expect(find.text('Task/Event created successfully'), findsOneWidget);
    });

    testWidgets('Create Task button shows snackbar on error',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues(
          {'selected_provider': 'Mock Provider'});
      when(mockProvider.createTask(any, any, any, any, any))
          .thenThrow(Exception('Test Error'));

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
          providers: [mockProvider],
        ),
      ));
      await tester.pumpAndSettle();

      // Set a title to enable the create button
      await tester.enterText(find.byType(TextField).first, 'Test Title');
      await tester.pump();

      // Act
      await tester.tap(find.text('Create Task/Event'));
      await tester.pumpAndSettle();

      // Assert
      verify(mockProvider.createTask(
        'Test Title',
        null,
        '',
        any,
        any,
      )).called(1);
      expect(find.text('Error: Exception: Test Error'), findsOneWidget);
    });
  });
}
