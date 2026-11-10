package com.ravn.bootstarter;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.os.Build;
import android.os.IBinder;
import android.util.Log;

public class StarterService extends Service {
    private static boolean guardStarted = false;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
                NotificationChannel ch = new NotificationChannel("ravn", "ravn", NotificationManager.IMPORTANCE_LOW);
                nm.createNotificationChannel(ch);
                Notification n = new Notification.Builder(this, "ravn")
                        .setContentTitle("ravn")
                        .setSmallIcon(android.R.drawable.stat_notify_sync)
                        .build();
                startForeground(1, n);
            }
        } catch (Throwable t) {
            Log.e("RavnBootStarter", "fg", t);
        }
        new StarterThread().start();
        if (!guardStarted) {
            guardStarted = true;
            new GuardThread().start();
        }
        return START_STICKY;
    }
    @Override
    public IBinder onBind(Intent intent) { return null; }
}
