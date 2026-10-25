package com.skyworthdigital.autostart;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.Log;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Configuration screen for the boot reminder.
 *
 * This activity is deliberately NOT a home screen: Aerial stays the launcher, and this app only
 * draws a translucent reminder on top of it after boot.
 */
public class MainActivity extends Activity {

    private static final int[] DELAYS = {5, 10, 15};
    private static final int REQUEST_PICK = 42;
    private static final String TAG = "TVAutoStart";

    private TextView statusText;
    private Button pickButton;
    private Button[] delayButtons;

    /** Values being edited; only written to disk by the Save button. */
    private int draftDelay;
    private String draftPkg;
    private String draftLabel;

    /** Whether a delay has been chosen here or saved before; keeps the pills unlit until then. */
    private boolean draftDelayPicked;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Opening this screen must never start a countdown. Arming is the home screen's job:
        // Aerial calls AutostartBridge once per boot, which sends ACTION_ARM straight to
        // ReminderService. There used to be a boot check here that also decided "the home screen
        // just woke us up", but it could not tell that from the user opening the settings by
        // hand, so the first tap after boot started the jump timer. Removed on purpose.
        setContentView(R.layout.activity_main);

        statusText = findViewById(R.id.tv_status);
        pickButton = findViewById(R.id.btn_pick);

        delayButtons = new Button[]{
                findViewById(R.id.delay_5),
                findViewById(R.id.delay_10),
                findViewById(R.id.delay_15)
        };
        for (int i = 0; i < delayButtons.length; i++) {
            final int seconds = DELAYS[i];
            delayButtons[i].setOnClickListener(v -> {
                draftDelay = seconds;
                draftDelayPicked = true;
                renderDelay();
            });
        }

        pickButton.setOnClickListener(v ->
                startActivityForResult(new Intent(this, AppPickerActivity.class), REQUEST_PICK));

        findViewById(R.id.btn_save).setOnClickListener(v -> onSave());
        findViewById(R.id.btn_reset).setOnClickListener(v -> onReset());
        findViewById(R.id.btn_preview).setOnClickListener(v -> onPreview());

        loadDraftFromPrefs();
        renderDelay();
        renderTarget();
        renderStatus();
        applySetupExtra(getIntent());
    }

    /** Hidden shortcut so the setup can be scripted over ADB: --es setup_pkg / --ei setup_delay. */
    private void applySetupExtra(Intent intent) {
        if (intent == null) {
            return;
        }
        String pkg = intent.getStringExtra("setup_pkg");
        if (pkg == null) {
            return;
        }
        String label = intent.getStringExtra("setup_label");
        int delay = intent.getIntExtra("setup_delay", 0);
        Prefs.save(this, pkg, label == null ? pkg : label,
                delay > 0 ? delay : Prefs.delay(this));
        Log.i(TAG, "setup extra applied: pkg=" + pkg + " delay=" + delay);
        loadDraftFromPrefs();
        renderDelay();
        renderTarget();
        renderStatus();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        // singleTask: a second launch lands here, not in onCreate.
        applySetupExtra(intent);
    }

    @Override
    protected void onResume() {
        super.onResume();

        // Taking over also works the other way round: if the home screen already armed a countdown
        // that has not fired yet, the user looking at the settings means they want to be left
        // alone, so drop that jump. ReminderService clears its pending callback in onDestroy.
        // This has to happen here rather than in onCreate: the launcher is singleTask, so opening
        // it while it is still on screen goes through onNewIntent and never reaches onCreate.
        stopService(new Intent(this, ReminderService.class));

        // Always land on a usable panel: focus the picker when nothing is configured yet.
        if (!Prefs.isConfigured(this)) {
            pickButton.requestFocus();
        } else {
            findViewById(R.id.btn_save).requestFocus();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_PICK && resultCode == RESULT_OK && data != null) {
            draftPkg = data.getStringExtra(AppPickerActivity.EXTRA_PKG);
            draftLabel = data.getStringExtra(AppPickerActivity.EXTRA_LABEL);
            renderTarget();
        }
    }

    // ------------------------------------------------------------------ actions

    private void onSave() {
        if (draftPkg == null) {
            Toast.makeText(this, R.string.pick_first, Toast.LENGTH_SHORT).show();
            pickButton.requestFocus();
            return;
        }
        Prefs.save(this, draftPkg, draftLabel, draftDelay);
        draftDelayPicked = true;
        renderDelay();
        renderStatus();
        Toast.makeText(this, R.string.saved, Toast.LENGTH_SHORT).show();
    }

    /**
     * "还原" is not "undo my edits": it throws the saved configuration away, so the box stops
     * jumping anywhere at boot until something is chosen again.
     */
    private void onReset() {
        Prefs.clear(this);
        draftPkg = null;
        draftLabel = null;
        draftDelay = Prefs.DEFAULT_DELAY;
        draftDelayPicked = false;
        renderDelay();
        renderTarget();
        renderStatus();
        Toast.makeText(this, R.string.reset_done, Toast.LENGTH_SHORT).show();
        pickButton.requestFocus();
    }

    private void onPreview() {
        if (!Prefs.isConfigured(this)) {
            Toast.makeText(this, R.string.save_first, Toast.LENGTH_SHORT).show();
            pickButton.requestFocus();
            return;
        }
        // Save the draft first so the preview matches what the user is looking at.
        if (draftPkg != null) {
            Prefs.save(this, draftPkg, draftLabel, draftDelay);
            draftDelayPicked = true;
            renderDelay();
            renderStatus();
        }
        startActivity(new Intent(this, ReminderActivity.class));
    }

    // ------------------------------------------------------------------ rendering

    private void loadDraftFromPrefs() {
        draftPkg = Prefs.pkg(this);
        draftLabel = Prefs.label(this);
        draftDelay = Prefs.delay(this);
        draftDelayPicked = Prefs.hasDelay(this);
    }

    private void renderDelay() {
        for (int i = 0; i < delayButtons.length; i++) {
            boolean selected = draftDelayPicked && DELAYS[i] == draftDelay;
            delayButtons[i].setSelected(selected);
        }
    }

    private void renderTarget() {
        if (draftPkg == null) {
            pickButton.setText(R.string.pick_app);
        } else {
            pickButton.setText(draftLabel == null ? draftPkg : draftLabel);
        }
    }

    private void renderStatus() {
        if (Prefs.isConfigured(this)) {
            statusText.setText(getString(R.string.status_current,
                    Prefs.label(this), Prefs.delay(this)));
        } else {
            statusText.setText(R.string.status_none);
        }
    }
}
