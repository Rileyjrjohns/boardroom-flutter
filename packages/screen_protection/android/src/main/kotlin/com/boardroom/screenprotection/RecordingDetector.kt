package com.boardroom.screenprotection

import android.app.Activity
import android.util.Log
import android.view.WindowManager
import java.lang.ref.WeakReference
import java.util.function.Consumer

private const val TAG = "ScreenProtection"

/**
 * Tells when the screen starts and stops being recorded while the app's window is visible. Android
 * 15 (API 35) and later only: `WindowManager.addScreenRecordingCallback` does not exist before, and
 * it needs the `DETECT_SCREEN_RECORDING` permission, declared in the manifest of this plugin. The
 * caller creates it only on a device that has the API.
 *
 * The callback belongs to the window manager of one activity: [attach] is called again for the
 * activity that replaces it, [detach] when it goes away or nobody listens. Neither throws. Main
 * thread only.
 */
class RecordingDetector(private val onChange: (captured: Boolean) -> Unit) {
    private var windowManager: WeakReference<WindowManager>? = null
    private var consumer: Consumer<Int>? = null

    /**
     * Starts reporting changes for this activity. Returns whether a recording is visible right now,
     * which the callback does not report (it only reports changes), or false when the detection is
     * unavailable.
     */
    fun attach(activity: Activity): Boolean {
        detach()
        val manager = activity.windowManager
        val callback = Consumer<Int> { state -> onChange(state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE) }
        return try {
            val initial = manager.addScreenRecordingCallback(mainExecutor, callback)
            windowManager = WeakReference(manager)
            consumer = callback
            initial == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
        } catch (error: SecurityException) {
            // The permission is not in the manifest of the build: the detection is off, nothing else is.
            Log.w(TAG, "Recording detection is unavailable: ${error.javaClass.simpleName}")
            false
        }
    }

    fun detach() {
        val manager = windowManager?.get()
        val callback = consumer
        windowManager = null
        consumer = null
        if (manager == null || callback == null) return
        try {
            manager.removeScreenRecordingCallback(callback)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Recording detection could not be stopped: ${error.javaClass.simpleName}")
        }
    }

    companion object {
        /** Whether a recording is visible right now, asked once, for nobody who is listening. */
        fun peek(activity: Activity): Boolean {
            val manager = activity.windowManager
            val callback = Consumer<Int> { }
            return try {
                val state = manager.addScreenRecordingCallback(mainExecutor, callback)
                manager.removeScreenRecordingCallback(callback)
                state == WindowManager.SCREEN_RECORDING_STATE_VISIBLE
            } catch (error: RuntimeException) {
                Log.w(TAG, "Recording state is unavailable: ${error.javaClass.simpleName}")
                false
            }
        }
    }
}
