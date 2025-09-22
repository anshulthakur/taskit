package me.bhaad.taskit

import android.content.Intent
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sharedText: String? = null
    private val PROCESS_TEXT_CHANNEL = "app.channel.process.data"
    private val CALENDAR_CHANNEL = "app.channel.calendar"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action
        val type = intent.type
        if (Intent.ACTION_PROCESS_TEXT == action && type == "text/plain") {
            sharedText = intent.getStringExtra(Intent.EXTRA_PROCESS_TEXT)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Handle text selection
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROCESS_TEXT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSharedText") {
                    result.success(sharedText)
                    sharedText = null
                } else {
                    result.notImplemented()
                }
            }
        // Handle calendar event insertion
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "addCalendarEvent") {
                    val title = call.argument<String>("title")
                    val description = call.argument<String>("description")
                    val startTime = call.argument<Long>("startTime")
                    val endTime = call.argument<Long>("endTime")
                    val intent = Intent(Intent.ACTION_INSERT).apply {
                        data = CalendarContract.Events.CONTENT_URI
                        putExtra(CalendarContract.Events.TITLE, title)
                        putExtra(CalendarContract.Events.DESCRIPTION, description)
                        putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startTime)
                        putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime)
                        // Optionally target Google Calendar specifically
                        //setPackage("com.google.android.calendar")
                    }
                    try {
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CALENDAR_ERROR", "Failed to add event: ${e.message}", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}