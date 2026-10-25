package com.skyworthdigital.autostart;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

/**
 * Fires the reminder once the box has booted.
 *
 * The receiver itself stays tiny: it hands the work to a foreground service, because Android 8+
 * refuses plain background service starts and Android 10 blocks background activities. Running in
 * the foreground is what makes the subsequent overlay launch legal.
 */
public class BootReceiver extends BroadcastReceiver {

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) {
            return;
        }
        String action = intent.getAction();
        boolean boot = Intent.ACTION_BOOT_COMPLETED.equals(action)
                || "android.intent.action.QUICKBOOT_POWERON".equals(action)
                || "com.htc.intent.action.QUICKBOOT_POWERON".equals(action);
        if (!boot) {
            return;
        }
        if (!Prefs.isConfigured(context)) {
            return;
        }
        // Bring the app out of its "stopped" state bookkeeping as early as possible.
        //
        // This path is a fallback: the firmware usually drops third-party BOOT_COMPLETED, and the
        // home screen arms us through ACTION_ARM instead. When it does get through, say who we are
        // and how long to wait - a bare Intent here used to look like "unknown source" to the
        // service, which then applied the boot grace on top of the user's countdown.
        Intent service = new Intent(context, ReminderService.class);
        service.setAction(ReminderService.ACTION_ARM);
        service.putExtra(ReminderService.EXTRA_WAIT_MS,
                Prefs.BOOT_GRACE_MS + Prefs.delay(context) * 1000L);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(service);
        } else {
            context.startService(service);
        }
    }
}
