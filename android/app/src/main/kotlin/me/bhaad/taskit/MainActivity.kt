package me.bhaad.taskit

import android.content.Intent
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager
import android.util.Log
import android.widget.Toast


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
            redirectToCalendar(sharedText ?: "")
            // ✅ Exit TaskIt after launching calendar
            finish()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                        redirectToCalendar(title ?: "", description, startTime, endTime)
                        result.success(true)
                    }
                    else -> {
                        Log.d(TAG, "Method not implemented: ${call.method}")
                        result.notImplemented()
                    }
                }
            }
    }

    private fun redirectToCalendar(
        title: String,
        description: String? = null,
        startTime: Long? = null,
        endTime: Long? = null
    ) {
        val prefs = getSharedPreferences("TaskItPrefs", MODE_PRIVATE)
        val preferredApp = prefs.getString("preferred_app", "com.google.android.calendar")
        val intent = Intent(Intent.ACTION_INSERT).apply {
            data = CalendarContract.Events.CONTENT_URI
            putExtra(CalendarContract.Events.TITLE, title.ifEmpty { "TaskIt Task" })
            putExtra(CalendarContract.Events.DESCRIPTION, description ?: "Created by TaskIt")
            putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, startTime ?: System.currentTimeMillis())
            putExtra(CalendarContract.EXTRA_EVENT_END_TIME, endTime ?: System.currentTimeMillis() + 3600000)
            addFlags(Intent.FLAG_ACTIVITY_NO_HISTORY) // ✅ Prevents calendar from staying in back stack
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (isPackageInstalled(preferredApp!!)) {
                setPackage(preferredApp)
                Log.d(TAG, "Targeting $preferredApp for title: $title")
            } else {
                Log.d(TAG, "Preferred app $preferredApp not installed, using generic intent")
            }
        }

        try {
            startActivity(intent)
            Toast.makeText(this, "Task created", Toast.LENGTH_SHORT).show() // ✅ Native toast
            Log.d(TAG, "Successfully launched calendar intent for title: $title")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to launch calendar intent: ${e.message}")
        }
    }

    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }
}
