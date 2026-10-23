package com.boardroom.screenprotection

/**
 * The last known state of the screen recording, so that a state is told once. The system reports changes
 * (and a state that was already known when a callback is registered again), and Dart is told only when
 * the state differs from the one it was told.
 */
class CaptureStateTracker {
    private var last: Boolean? = null

    /** Records [captured] and returns whether it differs from the state known before (a first state counts as known, not changed). */
    fun record(captured: Boolean): Boolean {
        val before = last
        last = captured
        return before != null && before != captured
    }

    /** The state known, or null when none was recorded since the last [forget]. */
    fun known(): Boolean? = last

    /** Forgets the state: nobody listens any more. */
    fun forget() {
        last = null
    }
}
