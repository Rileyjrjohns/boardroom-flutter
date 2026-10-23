package com.boardroom.screenprotection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class CaptureStateTrackerTest {
    @Test
    fun theFirstStateIsKnownButIsNotAChange() {
        val tracker = CaptureStateTracker()

        assertFalse(tracker.record(true))
        assertEquals(true, tracker.known())
    }

    @Test
    fun tellsAChangeOnceAndDropsARepeat() {
        val tracker = CaptureStateTracker()
        tracker.record(false)

        assertTrue(tracker.record(true))
        assertFalse(tracker.record(true))
        assertTrue(tracker.record(false))
        assertFalse(tracker.record(false))
    }

    @Test
    fun forgetsTheStateWhenNobodyListens() {
        val tracker = CaptureStateTracker()
        tracker.record(true)

        tracker.forget()

        assertNull(tracker.known())
        assertFalse(tracker.record(false))
    }
}
