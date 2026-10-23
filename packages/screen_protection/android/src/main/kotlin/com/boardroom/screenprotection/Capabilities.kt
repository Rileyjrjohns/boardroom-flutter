package com.boardroom.screenprotection

import android.os.Build

/** What an Android version can do for the screen protection. */
object Capabilities {
    /** The first version with `Activity.ScreenCaptureCallback` (Android 14). */
    const val SCREENSHOT_DETECTION_SDK = Build.VERSION_CODES.UPSIDE_DOWN_CAKE

    /** The first version with `WindowManager.addScreenRecordingCallback` (Android 15). */
    const val RECORDING_DETECTION_SDK = Build.VERSION_CODES.VANILLA_ICE_CREAM

    /**
     * The protection (`FLAG_SECURE`) works on every supported version, the detections only from the
     * versions that have the API. There is no secure view to report: the window flag covers everything.
     */
    fun forSdk(sdk: Int) = ProtectionCapabilities(
        protection = true,
        screenshotDetection = sdk >= SCREENSHOT_DETECTION_SDK,
        recordingDetection = sdk >= RECORDING_DETECTION_SDK,
        secureView = false,
    )
}
