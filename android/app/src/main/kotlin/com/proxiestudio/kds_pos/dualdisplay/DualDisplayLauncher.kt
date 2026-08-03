package com.proxiestudio.kds_pos.dualdisplay

import android.content.Context
import android.hardware.display.DisplayManager
import android.util.Log
import android.view.Display

/**
 * Detects the Sunmi D3 mini's secondary customer-facing panel and shows a
 * [CustomerDisplayPresentation] on it, rather than launching a second Activity onto it (which
 * requires cross-display activity-launch permissions many OEMs withhold for a private customer
 * panel, and is what crashed on-device).
 *
 * Detection matches on [Display.FLAG_PRESENTATION] - the flag Android defines specifically to
 * mark a display as suitable for [android.app.Presentation] - via a plain scan of every
 * [Display] rather than `DisplayManager.getDisplays(DISPLAY_CATEGORY_PRESENTATION)`, which is
 * (per Sunmi's docs, https://docs.sunmi.com/en-US/cdixeghjk491/xfcfeghjk535) not guaranteed to
 * agree with the real secondary panel on this hardware. Requiring `FLAG_SECURE` and
 * `FLAG_SUPPORTS_PROTECTED_BUFFERS` in addition (as Sunmi's own older sample does) turned out to
 * be too strict for the D3 mini and matched no display at all, which silently fell back to
 * single-screen mode and left the customer panel mirroring the main screen instead - so this
 * checks `FLAG_PRESENTATION` alone.
 *
 * On any device without a matching secondary display (dev phone, emulator, disconnected
 * panel), this is a no-op and the app falls back to exactly the single-screen behaviour it had
 * before this feature existed. Unlike `SoftPayPlugin`'s relay decision (checked live per charge
 * attempt), showing the Presentation itself only needs to happen once a display shows up - it
 * stays up for as long as the display is attached, so a one-time check here plus a
 * [DisplayManager.DisplayListener] for later hot-plugs is enough; it's never allowed to crash
 * the app.
 */
object DualDisplayLauncher {

    private const val TAG = "DualDisplayLauncher"

    @Volatile private var currentPresentation: CustomerDisplayPresentation? = null
    private var listenerRegistered = false

    /** Call once the host activity is fully resumed (e.g. from `onPostResume`). */
    fun showIfAvailable(context: Context) {
        presentationDisplay(context)?.let { showPresentation(context, it) }
        registerListener(context)
    }

    fun onPresentationDismissed(presentation: CustomerDisplayPresentation) {
        if (currentPresentation === presentation) currentPresentation = null
    }

    private fun displayManager(context: Context): DisplayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    private fun presentationDisplay(context: Context): Display? {
        val displays = displayManager(context).displays
        Log.i(TAG, "Enumerating displays: ${displays.joinToString { "${it.displayId}(flags=${it.flags})" }}")
        return displays.firstOrNull { (it.flags and Display.FLAG_PRESENTATION) != 0 }
    }

    private fun registerListener(context: Context) {
        if (listenerRegistered) return
        listenerRegistered = true
        displayManager(context).registerDisplayListener(
            object : DisplayManager.DisplayListener {
                override fun onDisplayAdded(displayId: Int) {
                    if (currentPresentation != null) return
                    presentationDisplay(context)?.let { showPresentation(context, it) }
                }

                // Presentation handles its own teardown via onDisplayRemoved(); nothing to do here.
                override fun onDisplayRemoved(displayId: Int) = Unit

                override fun onDisplayChanged(displayId: Int) = Unit
            },
            null,
        )
    }

    private fun showPresentation(context: Context, display: Display) {
        if (currentPresentation != null) return
        try {
            val presentation = CustomerDisplayPresentation(context, display)
            presentation.setOnDismissListener { onPresentationDismissed(presentation) }
            presentation.show()
            currentPresentation = presentation
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to show CustomerDisplayPresentation on display ${display.displayId}", e)
        }
    }
}
