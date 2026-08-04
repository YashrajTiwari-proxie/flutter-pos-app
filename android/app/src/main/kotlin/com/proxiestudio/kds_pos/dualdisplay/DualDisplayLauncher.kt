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
 * Detection uses `DisplayManager.getDisplays(DISPLAY_CATEGORY_PRESENTATION)` - confirmed working
 * on this exact D3 mini unit by testing Sunmi's own ClientView reference app
 * (https://docs.sunmi.com/en-US/cdixeghjk491/xmmqeghjk513), which uses this identical call.
 * (Requiring `FLAG_SECURE` and `FLAG_SUPPORTS_PROTECTED_BUFFERS` in addition, per an older Sunmi
 * sample, matched no display at all on this unit - don't reintroduce that.)
 *
 * Deliberately NOT triggered automatically at app startup/resume: the panel isn't reliably
 * presentation-capable that early (confirmed - even Sunmi's own ClientView app couldn't find it
 * on an immediate check, only once the app had been running/interacted with for a bit), and an
 * automatic retry loop after resume still didn't resolve it either. So instead, [activate] is
 * called on an explicit staff action (a button in the Employee Terminal UI - see
 * `DisplayBridgePlugin`'s `activateSecondaryDisplay`), mirroring ClientView's own manual "Show"
 * button, to isolate whether on-demand triggering behaves differently. Never allowed to crash
 * the app.
 */
object DualDisplayLauncher {

    private const val TAG = "DualDisplayLauncher"

    @Volatile private var currentPresentation: CustomerDisplayPresentation? = null

    /** Call on an explicit staff action. Returns true if the customer display is now showing
     *  (either just activated, or was already active), false if no matching display was found. */
    fun activate(context: Context): Boolean {
        presentationDisplay(context)?.let { showPresentation(context, it) }
        return currentPresentation != null
    }

    fun onPresentationDismissed(presentation: CustomerDisplayPresentation) {
        if (currentPresentation === presentation) currentPresentation = null
    }

    private fun displayManager(context: Context): DisplayManager =
        context.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    private fun presentationDisplay(context: Context): Display? {
        val manager = displayManager(context)
        Log.i(
            TAG,
            "Enumerating displays: ${manager.displays.joinToString { "${it.displayId}(flags=${it.flags})" }}",
        )
        return manager.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull()
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
