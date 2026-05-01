package org.esr.soma_alarm

import android.accounts.AccountManager
import android.content.ContentResolver
import android.content.ContentUris
import android.database.Cursor
import android.os.Bundle
import android.provider.CalendarContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.esr.soma_alarm/calendar")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInstances" -> {
                        val beginMs = call.argument<Long>("begin") ?: System.currentTimeMillis()
                        val endMs = call.argument<Long>("end") ?: (beginMs + 86400000L)
                        try {
                            result.success(queryInstances(beginMs, endMs))
                        } catch (e: Exception) {
                            result.error("CALENDAR_ERROR", e.message, null)
                        }
                    }
                    "requestSync" -> {
                        try {
                            result.success(requestCalendarSync())
                        } catch (e: Exception) {
                            result.error("SYNC_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestCalendarSync(): Boolean {
        val am = AccountManager.get(this)
        val accounts = am.getAccountsByType("com.google")
        if (accounts.isEmpty()) return false
        for (account in accounts) {
            val extras = Bundle().apply {
                putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
                putBoolean(ContentResolver.SYNC_EXTRAS_EXPEDITED, true)
            }
            ContentResolver.requestSync(account, CalendarContract.AUTHORITY, extras)
        }
        return true
    }

    private fun queryInstances(beginMs: Long, endMs: Long): List<Map<String, Any?>> {
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, beginMs)
        ContentUris.appendId(builder, endMs)

        val projection = arrayOf(
            CalendarContract.Instances.EVENT_ID,
            CalendarContract.Instances.TITLE,
            CalendarContract.Instances.BEGIN,
            CalendarContract.Instances.END,
            CalendarContract.Instances.EVENT_LOCATION,
            CalendarContract.Instances.CALENDAR_ID,
            CalendarContract.Instances.ALL_DAY,
        )

        val cursor: Cursor? = contentResolver.query(
            builder.build(), projection, null, null,
            "${CalendarContract.Instances.BEGIN} ASC"
        )

        val events = mutableListOf<Map<String, Any?>>()
        cursor?.use {
            while (it.moveToNext()) {
                events.add(mapOf(
                    "event_id" to it.getLong(0).toString(),
                    "title" to (it.getString(1) ?: ""),
                    "begin" to it.getLong(2),
                    "end" to it.getLong(3),
                    "location" to it.getString(4),
                    "calendar_id" to it.getString(5),
                    "all_day" to (it.getInt(6) == 1),
                ))
            }
        }
        return events
    }
}
