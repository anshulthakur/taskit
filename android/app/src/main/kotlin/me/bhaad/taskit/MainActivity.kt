package me.bhaad.taskit

import android.content.Intent
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.util.Log

class MainActivity : FlutterActivity() {
    private var sharedText: String? = null
    private val PROCESS_TEXT_CHANNEL = "app.channel.process.data"
    private val CALENDAR_CHANNEL = "app.channel.calendar"
    private val TAG = "MainActivity"

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
            Log.d(TAG, "Received shared text: $sharedText")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Handle shared text channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PROCESS_TEXT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getSharedText") {
                    Log.d(TAG, "getSharedText called, returning: $sharedText")
                    result.success(sharedText)
                    sharedText = null
                } else {
                    Log.d(TAG, "Method not implemented: ${call.method}")
                    result.notImplemented()
                }
            }
        // Handle calendar-related methods
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPackageInstalled" -> {
                        val packageName = call.argument<String>("packageName")
                        try {
                            packageManager.getPackageInfo(packageName!!, 0)
                            Log.d(TAG, "Package $packageName is installed")
                            result.success(true)
                        } catch (e: PackageManager.NameNotFoundException) {
                            Log.d(TAG, "Package $packageName is not installed: ${e.message}")
                            result.success(false)
                        }
                    }
                    "addGoogleCalendarEvent" -> {
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
                            // Target Google Calendar if installed
                            try {
                                packageManager.getPackageInfo("com.google.android.calendar", 0)
                                setPackage("com.google.android.calendar")
                                Log.d(TAG, "Targeting Google Calendar intent for title: $title")
                            } catch (e: PackageManager.NameNotFoundException) {
                                Log.d(TAG, "Google Calendar not installed, using generic intent")
                            }
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        try {
                            val resolvedInfo = intent.resolveActivityInfo(packageManager, 0)
                            if (resolvedInfo != null) {
                                startActivity(intent)
                                Log.d(TAG, "Successfully launched calendar intent for title: $title, resolved to ${resolvedInfo.packageName}/${resolvedInfo.name}")
                                result.success(true)
                            } else {
                                Log.d(TAG, "No activity available to handle calendar intent for title: $title")
                                result.success(false)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to add event via calendar intent: ${e.message}")
                            result.success(false)
                        }
                    }
                    else -> {
                        Log.d(TAG, "Method not implemented: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
    }
}