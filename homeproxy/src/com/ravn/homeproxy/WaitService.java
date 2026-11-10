package com.ravn.homeproxy;

import android.app.Service;
import android.content.ComponentName;
import android.content.Intent;
import android.os.IBinder;

import java.io.File;

/**
 * Waits (off the main thread) until /dev/rtc0 is writable, then starts Centaur.
 *
 * HomeActivity cannot wait itself: it uses Theme.NoDisplay, and Android throws
 * "did not call finish() prior to onResume() completing" if such an activity
 * stays alive. A short-lived service has no such restriction, and the process
 * survives long enough for the watcher to chmod /dev/rtc0 at boot.
 */
public final class WaitService extends Service {
    private static final String CENTAUR = "ru.yandex.quasar.centaur_app";
    private static final String CENTAUR_MAIN = "ru.yandex.quasar.centaur_app.MainActivity";
    private static final File RTC = new File("/dev/rtc0");
    private static final long RETRY_MS = 400;
    private static final long MAX_WAIT_MS = 30000;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        new Thread(() -> {
            long waited = 0;
            while (!RTC.canWrite() && waited < MAX_WAIT_MS) {
                try {
                    Thread.sleep(RETRY_MS);
                } catch (InterruptedException e) {
                    break;
                }
                waited += RETRY_MS;
            }
            try {
                Intent i = new Intent(Intent.ACTION_MAIN);
                i.setComponent(new ComponentName(CENTAUR, CENTAUR_MAIN));
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                startActivity(i);
            } catch (Throwable ignored) {
                // fall through: system home resolution will take over
            }
            stopSelf(startId);
        }).start();
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
