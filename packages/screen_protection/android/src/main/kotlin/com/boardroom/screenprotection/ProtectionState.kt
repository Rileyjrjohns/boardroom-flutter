package com.boardroom.screenprotection

/** The part of a window the protection acts on. A real window sets or clears `FLAG_SECURE`; a test records the calls. */
interface SecureWindow {
    fun setSecure(secure: Boolean)
}

/**
 * Whether the protection is on, and the window it is applied to.
 *
 * The flag belongs to a window, and the activity (so its window) is replaced when the system recreates
 * it, so the switch remembers what was asked and applies it again to each window it is given. With no
 * window yet it only remembers: the window it gets later is protected as soon as it comes.
 */
class ProtectionState {
    var enabled: Boolean = false
        private set

    private var window: SecureWindow? = null

    /** Asks for the protection to be on or off, and applies it to the current window if there is one. */
    fun setEnabled(enabled: Boolean) {
        this.enabled = enabled
        window?.setSecure(enabled)
    }

    /** Gives the window the protection acts on (null when the activity is gone), and applies what was asked. */
    fun attach(window: SecureWindow?) {
        this.window = window
        window?.setSecure(enabled)
    }

    /** Turns the protection off and lets go of the window, leaving it as it was found. */
    fun reset() {
        setEnabled(false)
        window = null
    }
}
