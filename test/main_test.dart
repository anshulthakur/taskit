
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskit/main.dart';

import 'main_test.mocks.dart';

// Generate mocks for the classes we need to mock
@GenerateMocks([MethodChannel, IntegrationProvider, SharedPreferences])
void main() {
  // Unit Tests
  group('Unit Tests', () {
    // Mock MethodChannel for processTextChannel
    final mockProcessTextChannel = MockMethodChannel();
    // Mock MethodChannel for calendarChannel
    final mockCalendarChannel = MockMethodChannel();

    // Set up mock handlers before each test
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        _processTextChannel,
        (MethodCall methodCall) async {
          return mockProcessTextChannel.invokeMethod(
              methodCall.method, methodCall.arguments);
        },
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        _calendarChannel,
        (MethodCall methodCall) async {
          return mockCalendarChannel.invokeMethod(
              methodCall.method, methodCall.arguments);
        },
      );
    });

    // Tear down mock handlers after each test
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_processTextChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_calendarChannel, null);
    });

    test('getSharedText returns shared text on success', () async {
      // Arrange
      const sharedText = 'This is a shared text';
      when(mockProcessTextChannel.invokeMethod('getSharedText'))
          .thenAnswer((_) async => sharedText);

      // Act
      final result = await getSharedText();

      // Assert
      expect(result, sharedText);
    });

    test('getSharedText returns null on failure', () async {
      // Arrange
      when(mockProcessTextChannel.invokeMethod('getSharedText'))
          .thenThrow(PlatformException(code: 'error'));

      // Act
      final result = await getSharedText();

      // Assert
      expect(result, isNull);
    });

    test('isPackageInstalled returns true when package is installed', () async {
      // Arrange
      when(mockCalendarChannel.invokeMethod(
              'isPackageInstalled', any))
          .thenAnswer((_) async => true);

      // Act
      final result = await isPackageInstalled('com.google.android.calendar');

      // Assert
      expect(result, isTrue);
    });

    test('isPackageInstalled returns false when package is not installed',
        () async {
      // Arrange
      when(mockCalendarChannel.invokeMethod(
              'isPackageInstalled', any))
          .thenAnswer((_) async => false);

      // Act
      final result = await isPackageInstalled('com.nonexistent.package');

      // Assert
      expect(result, isFalse);
    });

    test('isPackageInstalled returns false on error', () async {
      // Arrange
      when(mockCalendarChannel.invokeMethod(
              'isPackageInstalled', any))
          .thenThrow(PlatformException(code: 'error'));

      // Act
      final result = await isPackageInstalled('com.google.android.calendar');

      // Assert
      expect(result, isFalse);
    });
  });

  // Widget Tests
  group('Widget Tests', () {
    late MockIntegrationProvider mockProvider;

    setUp(() {
      mockProvider = MockIntegrationProvider();
      when(mockProvider.name).thenReturn('Mock Provider');

      // Mock the calendar channel for all widget tests in this group
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_calendarChannel, (MethodCall methodCall) async {
        if (methodCall.method == 'isPackageInstalled') {
          return false; // Assume package is not installed for tests
        }
        return null;
      });
    });

    tearDown(() {
      // Clean up the mock handler after each test
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_calendarChannel, null);
    });

    testWidgets('HomeScreen shows loading indicator and then main UI',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues({});

      // Act
      await tester.pumpWidget(const TaskitApp());

      // Assert
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Act
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('TaskIt'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(ElevatedButton), findsNWidgets(2));
    });

    testWidgets('HomeScreen displays shared text', (WidgetTester tester) async {
      // Arrange
      const sharedText = 'Test shared text';
      SharedPreferences.setMockInitialValues({});
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        _processTextChannel,
        (MethodCall methodCall) async => sharedText,
      );

      // Act
      await tester.pumpWidget(const TaskitApp());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Selected/Shared Text: $sharedText'), findsOneWidget);
      expect(find.widgetWithText(TextField, sharedText), findsNWidgets(2));

      // Clean up the mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_processTextChannel, null);
    });

    testWidgets('Can select a date and time', (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const TaskitApp());
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text('Select Date/Time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Not set'), findsNothing);
    });

    testWidgets('Create Task button calls provider and shows snackbar on success',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues({'selected_provider': 'Mock Provider'});
      when(mockProvider.createTask(any, any, any, any, any))
          .thenAnswer((_) async {});

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(providers: [mockProvider]),
      ));
      await tester.pumpAndSettle();

      // Set a title to enable the create button
      await tester.enterText(find.byType(TextField).first, 'Test Title');
      await tester.pump();

      // Act
      await tester.tap(find.text('Create Task/Event'));
      await tester.pumpAndSettle();

      // Assert
      verify(mockProvider.createTask('Test Title', null, null, false, any))
          .called(1);
      expect(find.text('Task/Event created successfully'), findsOneWidget);
    });

    testWidgets('Create Task button shows snackbar on error',
        (WidgetTester tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues({'selected_provider': 'Mock Provider'});
      when(mockProvider.createTask(any, any, any, any, any))
          .thenThrow(Exception('Test Error'));

      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(providers: [mockProvider]),
      ));
      await tester.pumpAndSettle();

      // Set a title to enable the create button
      await tester.enterText(find.byType(TextField).first, 'Test Title');
      await tester.pump();

      // Act
      await tester.tap(find.text('Create Task/Event'));
      await tester.pumpAndSettle();

      // Assert
      verify(mockProvider.createTask('Test Title', null, null, false, any))
          .called(1);
      expect(find.text('Error: Exception: Test Error'), findsOneWidget);
    });
  });
}

// Helper constants for MethodChannel names to avoid typos
const MethodChannel _processTextChannel =
    MethodChannel('app.channel.process.data');
const MethodChannel _calendarChannel = MethodChannel('app.channel.calendar');

