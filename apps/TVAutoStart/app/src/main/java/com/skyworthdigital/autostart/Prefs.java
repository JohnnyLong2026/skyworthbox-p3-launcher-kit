package com.skyworthdigital.autostart;

import android.content.Context;
import android.content.SharedPreferences;

/** Tiny wrapper around the saved auto-start configuration. */
final class Prefs {

    static final String FILE = "autostart";
    static final String KEY_PKG = "target_pkg";
    static final String KEY_LABEL = "target_label";
    static final String KEY_DELAY = "delay_seconds";

    static final int DEFAULT_DELAY = 10;

    /**
     * Fallback wait used only when something starts this service without saying who it is (no
     * ACTION_ARM, no explicit wait). On this box that path never happens - BOOT_COMPLETED is
     * filtered by the firmware - so it is kept short: the old 15s value silently became "15s +
     * your countdown" whenever the action got lost, which read as "the popup takes forever".
     */
    static final long BOOT_GRACE_MS = 3_000L;

    private Prefs() {
    }

    static SharedPreferences get(Context context) {
        return context.getSharedPreferences(FILE, Context.MODE_PRIVATE);
    }

    static String pkg(Context context) {
        return get(context).getString(KEY_PKG, null);
    }

    static String label(Context context) {
        return get(context).getString(KEY_LABEL, null);
    }

    static int delay(Context context) {
        return get(context).getInt(KEY_DELAY, DEFAULT_DELAY);
    }

    static boolean isConfigured(Context context) {
        String pkg = pkg(context);
        return pkg != null && !pkg.isEmpty();
    }

    /** True once a delay has been saved, so the panel can leave every pill unlit before that. */
    static boolean hasDelay(Context context) {
        return get(context).contains(KEY_DELAY);
    }

    /** Back to a blank slate: the next boot does nothing until the owner sets it up again. */
    static void clear(Context context) {
        get(context).edit()
                .remove(KEY_PKG)
                .remove(KEY_LABEL)
                .remove(KEY_DELAY)
                .apply();
    }

    static void save(Context context, String pkg, String label, int delaySeconds) {
        get(context).edit()
                .putString(KEY_PKG, pkg)
                .putString(KEY_LABEL, label == null ? pkg : label)
                .putInt(KEY_DELAY, delaySeconds)
                .apply();
    }
}
