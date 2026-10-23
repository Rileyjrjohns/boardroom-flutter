package com.boardroom.screenprotection

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

private class RecordingWindow : SecureWindow {
    val calls = mutableListOf<Boolean>()

    override fun setSecure(secure: Boolean) {
        calls.add(secure)
    }
}

internal class ProtectionStateTest {
    @Test
    fun appliesWhatIsAskedToTheCurrentWindow() {
        val state = ProtectionState()
        val window = RecordingWindow()
        state.attach(window)

        state.setEnabled(true)
        state.setEnabled(false)

        assertEquals(listOf(false, true, false), window.calls)
    }

    @Test
    fun remembersTheProtectionWhenThereIsNoWindowAndAppliesItWhenOneComes() {
        val state = ProtectionState()
        state.setEnabled(true)
        val window = RecordingWindow()

        state.attach(window)

        assertTrue(state.enabled)
        assertEquals(listOf(true), window.calls)
    }

    @Test
    fun protectsTheWindowThatReplacesTheOldOne() {
        val state = ProtectionState()
        state.attach(RecordingWindow())
        state.setEnabled(true)
        val recreated = RecordingWindow()

        state.attach(recreated)

        assertEquals(listOf(true), recreated.calls)
    }

    @Test
    fun doesNotTouchTheWindowOfAnActivityThatIsGone() {
        val state = ProtectionState()
        val window = RecordingWindow()
        state.attach(window)
        state.attach(null)

        state.setEnabled(true)

        assertEquals(listOf(false), window.calls)
    }

    @Test
    fun resetTurnsTheProtectionOffAndLetsGoOfTheWindow() {
        val state = ProtectionState()
        val window = RecordingWindow()
        state.attach(window)
        state.setEnabled(true)

        state.reset()

        assertFalse(state.enabled)
        state.setEnabled(true)
        assertEquals(listOf(false, true, false), window.calls)
    }
}
