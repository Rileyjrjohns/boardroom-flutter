package com.boardroom.screenprotection

import kotlin.test.Test
import kotlin.test.assertEquals

internal class CapabilitiesTest {
    @Test
    fun protectsEveryVersionAndDetectsFromTheVersionsThatHaveTheApi() {
        assertEquals(
            ProtectionCapabilities(protection = true, screenshotDetection = false, recordingDetection = false, secureView = false),
            Capabilities.forSdk(33),
        )
        assertEquals(
            ProtectionCapabilities(protection = true, screenshotDetection = true, recordingDetection = false, secureView = false),
            Capabilities.forSdk(34),
        )
        assertEquals(
            ProtectionCapabilities(protection = true, screenshotDetection = true, recordingDetection = true, secureView = false),
            Capabilities.forSdk(35),
        )
    }
}
