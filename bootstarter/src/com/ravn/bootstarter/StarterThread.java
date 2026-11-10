package com.ravn.bootstarter;

import android.util.Log;

public class StarterThread extends Thread {
    public StarterThread() { }
    @Override
    public void run() {
        try { Thread.sleep(15000L); } catch (InterruptedException e) { }
        while (true) {
            try {
                Log.i("RavnBootStarter", "starting watcher via localhost adb");
                AdbStarter.run();
                Log.i("RavnBootStarter", "adb connection ended; retrying");
            } catch (Throwable t) {
                Log.i("RavnBootStarter", "starter error " + t);
            }
            try { Thread.sleep(2000L); } catch (InterruptedException e) { }
        }
    }
}
