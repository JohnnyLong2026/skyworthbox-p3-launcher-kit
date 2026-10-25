package com.skyworthdigital.autostart;

import android.app.Activity;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.os.Bundle;
import android.os.CountDownTimer;
import android.view.KeyEvent;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Locale;

/**
 * Translucent reminder window that floats on top of the CleanYourTV home screen.
 *
 * It shows the configured app and a countdown. If the user does nothing, the target app is opened
 * when the countdown hits zero. Any remote keypress cancels this run and dismisses the window, so
 * the window deliberately holds no focusable widgets.
 */
public class ReminderActivity extends Activity {

    /** How long the reminder stays on screen before jumping, giving the user time to cancel. */
    private static final int NOTICE_SECONDS = 9;

    private TextView countText;
    private TextView targetText;
    private ProgressBar progress;

    private CountDownTimer timer;
    private boolean launching;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!Prefs.isConfigured(this)) {
            finish();
            return;
        }
        setContentView(R.layout.activity_reminder);

        countText = findViewById(R.id.tv_count);
        targetText = findViewById(R.id.tv_target);
        progress = findViewById(R.id.progress);

        startCountdown();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        // Already on screen: keep the running countdown instead of restarting it.
    }

    @Override
    protected void onPause() {
        super.onPause();
        if (!launching) {
            // Lost the foreground for any other reason; drop the reminder rather than fire blind.
            cancelCountdown();
            finish();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        cancelCountdown();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        // Any key on the remote aborts this run.
        cancelAndFinish();
        return true;
    }

    // ------------------------------------------------------------------ countdown

    private void startCountdown() {
        int seconds = NOTICE_SECONDS;
        String label = Prefs.label(this);

        countText.setText(String.valueOf(seconds));
        // The card says "秒后自动跳转" on its own line, so this one is just the app's name.
        targetText.setText(label == null ? "" : label);

        progress.setMax(seconds * 10);
        progress.setProgress(seconds * 10);

        timer = new CountDownTimer(seconds * 1000L, 100L) {
            @Override
            public void onTick(long millisUntilFinished) {
                long tenths = (millisUntilFinished + 99) / 100;
                countText.setText(String.valueOf((tenths + 9) / 10));
                progress.setProgress((int) tenths);
            }

            @Override
            public void onFinish() {
                timer = null;
                countText.setText("0");
                progress.setProgress(0);
                launchTarget();
            }
        }.start();
    }

    private void cancelCountdown() {
        if (timer != null) {
            timer.cancel();
            timer = null;
        }
    }

    private void cancelAndFinish() {
        if (launching) {
            return;
        }
        cancelCountdown();
        finish();
    }

    private void launchTarget() {
        String pkg = Prefs.pkg(this);
        if (pkg == null) {
            finish();
            return;
        }
        PackageManager pm = getPackageManager();
        Intent intent = pm.getLeanbackLaunchIntentForPackage(pkg);
        if (intent == null) {
            intent = pm.getLaunchIntentForPackage(pkg);
        }
        if (intent == null) {
            Toast.makeText(this, R.string.launch_failed, Toast.LENGTH_LONG).show();
            finish();
            return;
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
        launching = true;
        try {
            startActivity(intent);
        } catch (Exception e) {
            Toast.makeText(this, R.string.launch_failed, Toast.LENGTH_LONG).show();
        }
        finish();
    }
}
