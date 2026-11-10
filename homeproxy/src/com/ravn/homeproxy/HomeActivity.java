package com.ravn.homeproxy;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;

/**
 * Invisible HOME target for SberPortal.
 *
 * Sber's gesture service turns a top-edge swipe into a HOME intent. Centaur's
 * own home component is ChironSplashActivity, which destroys and recreates
 * MainActivity; that costs seconds and loses the cached top-sheet Div, so the
 * user sees an empty screen before the sheet appears.
 *
 * This activity is launched by HOME instead. It starts WaitService (which
 * waits for /dev/rtc0 to become writable at boot and then resumes Centaur's
 * MainActivity without recreating it) and finishes immediately: a NoDisplay
 * activity must not stay alive past onResume.
 *
 * Only lambdas are used: d8 34.0.0 crashes on a javac-generated anonymous
 * class file (R8 NPE).
 */
public final class HomeActivity extends Activity {
    private static final String NETFIX = "com.rupleide.netfix";
    private static final String NETFIX_ACTIVITY = "com.rupleide.netfix.MainActivity";
    private static final String PREFS = "homeproxy";
    private static final String KEY_LAST_HOME_MS = "last_home_ms";
    private static final long DOUBLE_TAP_MS = 1600;

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        SharedPreferences p = getSharedPreferences(PREFS, MODE_PRIVATE);
        long now = System.currentTimeMillis();
        long last = p.getLong(KEY_LAST_HOME_MS, 0L);
        // Two HOME gestures in a row: open NetFix.
        boolean netfix = last > 0 && (now - last) <= DOUBLE_TAP_MS;
        p.edit().putLong(KEY_LAST_HOME_MS, netfix ? 0L : now).apply();

        if (netfix) {
            try {
                Intent i = new Intent(Intent.ACTION_MAIN);
                i.setClassName(NETFIX, NETFIX_ACTIVITY);
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
            } catch (Throwable ignored) {
                // fall back to Centaur below
                startService(new Intent(this, WaitService.class));
            }
        } else {
            startService(new Intent(this, WaitService.class));
        }
        finish();
    }
}
