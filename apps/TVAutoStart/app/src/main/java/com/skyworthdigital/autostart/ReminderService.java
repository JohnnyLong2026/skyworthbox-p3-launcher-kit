package com.skyworthdigital.autostart;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;

/**
 * Short-lived foreground service used only to make {@link ReminderActivity} legal to launch.
 *
 * Android 10 blocks activities launched from the background, but an app holding a foreground
 * service counts as foreground. So the service waits out {@link Prefs#BOOT_GRACE_MS} (letting the
 * home screen settle), opens the overlay, then shuts itself down.
 */
public class ReminderService extends Service {

    private static final String CHANNEL_ID = "autostart_reminder";
    private static final int NOTIFICATION_ID = 7001;

    /** Explicit wait, used when the home screen arms us (it already waited for itself to draw). */
    public static final String EXTRA_WAIT_MS = "wait_ms";

    /**
     * Sent by whichever home screen owns the box: "this is a fresh boot, run the timed start".
     * Needed on firmwares that block third-party BOOT_COMPLETED receivers entirely, where only the
     * home screen - already running at power-on - can wake this app.
     */
    public static final String ACTION_ARM = "com.ktcp.launcher.autostart.ACTION_ARM";

    /** The home screen has already drawn itself, so it only needs a beat before we pop up. */
    private static final long HOME_GRACE_MS = 1_000L;

    /** Re-check the deadline this often instead of trusting one long postDelayed. */
    private static final long TICK_MS = 250L;

    private static final String TAG = "TVAutoStart";

    private final Handler handler = new Handler(Looper.getMainLooper());

    /** Wall-clock deadline on elapsedRealtime, which keeps counting while the box dozes. */
    private long fireAtElapsedMs;

    /**
     * Once armed, stay armed until this process dies. Two independent paths can arm us on the same
     * boot (Aerial's AutostartBridge and, when the firmware lets it through, BootReceiver), and the
     * later one used to win by simply overwriting the deadline - which is how a 6s countdown became
     * a 20s one.
     */
    private boolean armed;

    /**
     * postDelayed alone is not enough here: on a freshly booted box the main thread is still busy
     * (wallpaper, weather, SystemUI) and the message landed ~3s late on top of a 20s wait. Every
     * tick compares against an absolute deadline, so lateness is corrected instead of accumulated.
     */
    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            long left = fireAtElapsedMs - SystemClock.elapsedRealtime();
            if (left > TICK_MS) {
                handler.postDelayed(this, TICK_MS);
            } else if (left > 0) {
                handler.postDelayed(this, left);
            } else {
                openReminder();
            }
        }
    };

    @Override
    public void onCreate() {
        super.onCreate();
        createChannel();
        startForeground(NOTIFICATION_ID, buildNotification());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (armed) {
            // First arm of this boot wins. Keep the earliest deadline instead of restarting it.
            Log.i(TAG, "already armed, ignoring extra start intent=" + (intent == null ? "null" : intent));
            return START_NOT_STICKY;
        }
        armed = true;
        handler.removeCallbacks(tick);
        long waitMs = intent != null ? intent.getLongExtra(EXTRA_WAIT_MS, -1L) : -1L;
        if (waitMs < 0) {
            // The home screen only calls once it has drawn itself, so the user's countdown starts
            // almost at once there. From BOOT_COMPLETED nothing is on screen yet, hence the grace.
            boolean fromHome = intent != null && ACTION_ARM.equals(intent.getAction());
            long grace = fromHome ? HOME_GRACE_MS : Prefs.BOOT_GRACE_MS;
            waitMs = grace + Prefs.delay(this) * 1000L;
            Log.i(TAG, "armed from " + (fromHome ? "home" : "unknown source")
                    + " action=" + (intent == null ? "null" : String.valueOf(intent.getAction()))
                    + " grace=" + grace + " delay=" + Prefs.delay(this) + " waitMs=" + waitMs);
        } else {
            Log.i(TAG, "armed with explicit waitMs=" + waitMs);
        }
        fireAtElapsedMs = SystemClock.elapsedRealtime() + waitMs;
        handler.postDelayed(tick, waitMs);
        return START_NOT_STICKY;
    }

    private void openReminder() {
        if (!Prefs.isConfigured(this)) {
            stopSelf();
            return;
        }
        Intent overlay = new Intent(this, ReminderActivity.class);
        overlay.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                | Intent.FLAG_ACTIVITY_CLEAR_TOP
                | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        try {
            startActivity(overlay);
        } catch (Exception ignored) {
            // Nothing we can do from a background context; the next boot will try again.
        }
        stopSelf();
    }

    private void createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return;
        }
        NotificationManager nm = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (nm == null || nm.getNotificationChannel(CHANNEL_ID) != null) {
            return;
        }
        NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID, getString(R.string.app_name), NotificationManager.IMPORTANCE_MIN);
        channel.setDescription(getString(R.string.notification_desc));
        nm.createNotificationChannel(channel);
    }

    private Notification buildNotification() {
        Notification.Builder builder;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new Notification.Builder(this, CHANNEL_ID);
        } else {
            builder = new Notification.Builder(this);
        }
        builder.setContentTitle(getString(R.string.notification_title))
                .setContentText(getString(R.string.notification_desc))
                .setSmallIcon(R.drawable.ic_alarm_notify)
                .setOngoing(false)
                .setPriority(Notification.PRIORITY_MIN);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN) {
            builder.setShowWhen(false);
        }
        return builder.build();
    }

    @Override
    public void onDestroy() {
        handler.removeCallbacks(tick);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
