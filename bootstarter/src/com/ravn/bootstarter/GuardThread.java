package com.ravn.bootstarter;

/**
 * Keeps /data/local/tmp/sber_guard.sh running.
 *
 * Killing ru.sberdevices.services makes StarOS clean up root/shell processes,
 * so the guard itself is killed together with its target.  This thread lives
 * in the app process (uid 10024), which survives that cleanup, and reconnects
 * over localhost adb as soon as the guard's pid is gone.
 */
public class GuardThread extends Thread {
    public GuardThread() { }

    @Override
    public void run() {
        try { Thread.sleep(5000L); } catch (InterruptedException e) { }
        while (true) {
            try {
                if (!AdbStarter.guardAlive()) {
                    AdbStarter.runGuard();
                }
            } catch (Throwable t) {
                // retry below
            }
            try { Thread.sleep(500L); } catch (InterruptedException e) { }
        }
    }
}
