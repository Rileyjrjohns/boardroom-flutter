package com.boardroom.screenprotection

import android.app.Activity
import android.os.Build
import android.view.WindowManager

/**
 * Screen protection for Android, behind the calls of Pigeon (`ScreenProtectionHostApi`) and the
 * stream of capture events.
 *
 * - **Protection.** While it is on, `FLAG_SECURE` is set on the window of the current activity: the
 *   system blocks screenshots and screen recordings of that window and shows a blank thumbnail in
 *   the recent apps. The flag belongs to a window, so [ProtectionState] sets it again on the window
 *   of each activity the plugin is given (the activity was recreated by a configuration change), and
 *   when there is no activity yet it only remembers that protection is on. Windows other than the one
 *   of the activity (a dialog) are not covered by it.
 * - **Screenshots** are reported on Android 14 and later ([ScreenshotDetector]); before that the
 *   system tells apps nothing.
 * - **Recording** is reported on Android 15 and later ([RecordingDetector]); before that, nothing.
 *
 * Threading: Pigeon runs the suspend functions on the main thread, the system delivers the callbacks
 * on the main thread, and so all state is read and written there. The detectors exist only while
 * somebody listens to the stream, and follow the activity when it changes.
 */
class ScreenProtectionHost : ScreenProtectionHostApi {
    private val protection = ProtectionState()
    private val captureState = CaptureStateTracker()
    private var activity: Activity? = null
    private var sink: PigeonEventSink<CaptureEventMessage>? = null
    private var screenshots: ScreenshotDetector? = null
    private var recordings: RecordingDetector? = null

    override suspend fun setProtectionEnabled(enabled: Boolean) {
        protection.setEnabled(enabled)
    }

    override suspend fun isCaptured(): Boolean {
        if (sink != null) captureState.known()?.let { return it }
        if (Build.VERSION.SDK_INT < Capabilities.RECORDING_DETECTION_SDK) return false
        val current = activity ?: return false
        return RecordingDetector.peek(current)
    }

    override fun capabilities(): ProtectionCapabilities = Capabilities.forSdk(Build.VERSION.SDK_INT)

    /** The activity the plugin is attached to changed (null when it is gone). */
    fun attachActivity(activity: Activity?) {
        this.activity = activity
        protection.attach(activity?.let { FlagSecureWindow(it) })
        if (sink == null) return
        if (activity == null) {
            detachDetectors()
        } else {
            attachDetectors(activity)
        }
    }

    /** Somebody started listening to the capture events. */
    fun startListening(sink: PigeonEventSink<CaptureEventMessage>) {
        this.sink = sink
        activity?.let { attachDetectors(it) }
    }

    /** Nobody listens any more: the callbacks of the system are removed. */
    fun stopListening() {
        sink = null
        detachDetectors()
        captureState.forget()
    }

    /** The plugin is detached from the engine: leave the window as found. */
    fun tearDown() {
        stopListening()
        protection.reset()
        activity = null
    }

    private fun attachDetectors(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Capabilities.SCREENSHOT_DETECTION_SDK) {
            val detector = screenshots ?: ScreenshotDetector { sink?.success(ScreenshotTakenMessage()) }.also { screenshots = it }
            detector.attach(activity)
        }
        if (Build.VERSION.SDK_INT >= Capabilities.RECORDING_DETECTION_SDK) {
            val detector = recordings ?: RecordingDetector { captured -> report(captured) }.also { recordings = it }
            // The callback reports changes only, so the state at the start is read here. When the detector
            // is attached again (the activity was recreated), a change that happened while it was off
            // is reported now.
            report(detector.attach(activity))
        }
    }

    private fun detachDetectors() {
        screenshots?.detach()
        recordings?.detach()
    }

    private fun report(captured: Boolean) {
        // The first state is not a change: Dart reads it with isCaptured. A change after it is told.
        if (captureState.record(captured)) {
            sink?.success(CaptureChangedMessage(captured = captured))
        }
    }
}

/** The window of an activity, protected by `FLAG_SECURE`. */
private class FlagSecureWindow(private val activity: Activity) : SecureWindow {
    override fun setSecure(secure: Boolean) {
        val window = activity.window
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
