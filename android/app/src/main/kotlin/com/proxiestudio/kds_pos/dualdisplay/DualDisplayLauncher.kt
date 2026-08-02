package com.proxiestudio.kds_pos.dualdisplay

import android.content.Context
import android.hardware.display.DisplayManager
import android.util.Log
import android.view.Display

/**
 * Detects the Sunmi D3 mini's secondary customer-facing panel and shows a
 * [CustomerDisplayPresentation] on it. Uses `DisplayManager.getDisplays
 * (DISPLAY_CATEGORY_PRESENTATION)` - the same query Sunmi's own docs recommend for this class
 * of device - rather than treating any non-default [Display] as a target, and rather than
 * launching a second Activity onto it (which requires cross-display activity-launch
 * permissions many OEMs withhold for a private customer panel, and is what crashed on-device).
 *
 * On any device without a presentation-capable secondary display (dev phone, emulator,
 * disconnected panel), this is a no-op and the app falls back to exactly the single-screen
 * behaviour it had before this feature existed.
 *
 * Detection ([hasPresentationDisplay]) and actually showing the presentation
 * ([showIfAvailable]) are deliberately separate calls: detection is a cheap, side-effect-free
 * query safe to run during `configureFlutterEngine` (used to pick which SoftPay plugin to
 * attach), while showing the presentation is only attempted once the host activity has fully
 * resumed, and is never allowed to crash the app.
 */
object DualDisplayLauncher {

    private const val TAG = "DualDisplayLauncher"

    @Volatile private var currentPresentation: CustomerDisplayPresentation? = null
    private var listenerRegistered = false

    fun hasPresentationDisplay(context: Context): Boolean = presentationDisplay(context) != null

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

    private fun presentationDisplay(context: Context): Display? =
        displayManager(context).getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION).firstOrNull()

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
