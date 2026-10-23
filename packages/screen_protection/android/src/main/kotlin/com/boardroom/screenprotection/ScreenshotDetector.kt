package com.boardroom.screenprotection

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.lang.ref.WeakReference
import java.util.concurrent.Executor

private const val TAG = "ScreenProtection"

/** Runs work on the main thread, where the callbacks of the activity are delivered. */
internal val mainExecutor: Executor = Handler(Looper.getMainLooper()).let { handler -> Executor { handler.post(it) } }

/**
 * Tells when a screenshot of the activity is taken. Android 14 (API 34) and later only: the callback
 * is an `Activity` API that does not exist before, and it needs the `DETECT_SCREEN_CAPTURE` permission,
 * declared in the manifest of this plugin. The caller creates it only on a device that has the API.
 *
 * The callback belongs to one activity. [attach] is called again for the activity that replaces it
 * (it was recreated); [detach] is called when the activity goes away or nobody listens. Both are
 * idempotent, and neither throws. Main thread only.
 */
class ScreenshotDetector(private val onScreenshot: () -> Unit) {
    private var activity: WeakReference<Activity>? = null
    private val callback = Activity.ScreenCaptureCallback { onScreenshot() }

    fun attach(target: Activity) {
        if (activity?.get() === target) return
        detach()
        try {
            target.registerScreenCaptureCallback(mainExecutor, callback)
            activity = WeakReference(target)
        } catch (error: SecurityException) {
            // The permission is not in the manifest of the build: the detection is off, nothing else is.
            Log.w(TAG, "Screenshot detection is unavailable: ${error.javaClass.simpleName}")
        }
    }

    fun detach() {
        val attached = activity?.get()
        activity = null
        if (attached == null) return
        try {
            attached.unregisterScreenCaptureCallback(callback)
        } catch (error: RuntimeException) {
            Log.w(TAG, "Screenshot detection could not be stopped: ${error.javaClass.simpleName}")
        }
    }
}
