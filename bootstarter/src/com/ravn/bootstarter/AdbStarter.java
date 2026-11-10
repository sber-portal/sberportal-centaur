package com.ravn.bootstarter;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.OutputStream;

public final class AdbStarter {
    private static final int CNXN = 0x4e584e43;
    private static final int OPEN = 0x4e45504f;
    private static final String BANNER = "host::features=shell_v2,cmd,stat_v2\u0000";

    /**
     * Makes the local adbd run as *capable* root (same effect as `adb root`),
     * then opens a root shell that keeps the watcher alive.
     *
     * After a cold boot adbd is uid=2000(shell).  The app itself cannot set
     * service.adb.root (property permission), but a shell connection over
     * localhost adbd can: adbd applies the property and restarts itself as
     * root.  u-boot already passes androidboot.rabbith.adb_root=1 + SELinux
     * permissive (see sberportal-root), so no Mac/adb root is needed.
     */
    public static void run() {
        try {
            for (int i = 0; i < 8; i++) {
                if (hasRootCaps()) {
                    startWatcher();
                    return;
                }
                // adbd starts as shell after a cold boot and cannot be rooted
                // by calling setprop from the app uid.  A shell connection to
                // localhost adbd can do it, though: adbd performs the restart
                // itself and comes back as uid 0.
                if (i == 0) rootAdbdViaShell();
                Thread.sleep(3000L);
            }
            startWatcher();
        } catch (Throwable t) {
            // fall through; the service is START_STICKY and will be restarted
        }
    }

    private static void rootAdbdViaShell() {
        shell("setprop service.adb.root 1; setprop ctl.restart adbd", 6000L);
    }

    /** Opens a throwaway shell and checks whether adbd gave us uid 0. */
    private static boolean hasRootCaps() {
        String out = shell("id; grep CapEff /proc/self/status", 6000L);
        if (out.contains("uid=0(")) return true;
        int i = out.indexOf("CapEff:");
        if (i < 0) return false;
        int j = i + 7;
        while (j < out.length() && (out.charAt(j) == ' ' || out.charAt(j) == '\t')) j++;
        int k = j;
        while (k < out.length() && isHex(out.charAt(k))) k++;
        if (k == j) return false;
        try {
            return Long.parseLong(out.substring(j, k), 16) != 0L;
        } catch (Throwable t) {
            return false;
        }
    }

    private static boolean isHex(char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    /** Runs a command through localhost adbd and returns everything it printed. */
    private static String shell(String cmd, long timeoutMs) {
        Process p = null;
        try {
            p = connect();
            OutputStream os = p.getOutputStream();
            InputStream is = p.getInputStream();
            send(os, CNXN, 0x01000000, 256 * 1024, BANNER.getBytes("UTF-8"));
            if (!readPacket(is, CNXN)) return "";
            send(os, OPEN, 1, 0, ("shell:" + cmd + "\u0000").getBytes("UTF-8"));
            ByteArrayOutputStream bos = new ByteArrayOutputStream();
            long deadline = System.currentTimeMillis() + timeoutMs;
            byte[] h = new byte[24];
            while (System.currentTimeMillis() < deadline) {
                if (!readFully(is, h)) break;
                int command = getInt(h, 0);
                int len = getInt(h, 12);
                if (command == 0x45545257) { // WRTE
                    byte[] pay = new byte[len];
                    if (!readFully(is, pay)) break;
                    bos.write(pay);
                } else if (command == 0x45534c43) { // CLSE
                    if (len > 0) readFully(is, new byte[len]);
                    break;
                } else if (len > 0) {
                    readFully(is, new byte[len]);
                }
            }
            return bos.toString("UTF-8");
        } catch (Throwable t) {
            return "";
        } finally {
            if (p != null) p.destroy();
        }
    }

    private static void startWatcher() throws Exception {
        Process p = connect();
        try {
            OutputStream os = p.getOutputStream();
            InputStream is = p.getInputStream();
            send(os, CNXN, 0x01000000, 256 * 1024, BANNER.getBytes("UTF-8"));
            if (!readPacket(is, CNXN)) return;
            String cmd = "chmod 666 /dev/rtc0 2>/dev/null; rm -rf /data/local/tmp/oat; "
                    + "exec env CLASSPATH=/data/local/tmp/centaur_watcher.dex app_process /system/bin "
                    + "CentaurSwipeWatcher >/data/local/tmp/centaur_watcher.out 2>&1";
            send(os, OPEN, 1, 0, ("shell:" + cmd + "\u0000").getBytes("UTF-8"));
            // Keep the connection (and therefore the watcher) alive forever.
            byte[] buf = new byte[4096];
            while (is.read(buf) != -1) { }
        } finally {
            p.destroy();
        }
    }

    /**
     * Same as {@link #run()} but keeps the Sber spotter guard alive instead of
     * the watcher.  StarOS kills root/shell processes when ru.sberdevices.services
     * is killed, so the guard is short-lived by design: this connection notices
     * it and the GuardThread restarts it immediately.
     */
    public static void runGuard() {
        try {
            for (int i = 0; i < 8; i++) {
                if (hasRootCaps()) {
                    startGuard();
                    return;
                }
                Thread.sleep(1000L);
            }
        } catch (Throwable t) {
            // GuardThread retries.
        }
    }

    public static boolean guardAlive() {
        try {
            java.io.BufferedReader r = new java.io.BufferedReader(
                    new java.io.FileReader("/data/local/tmp/sber_guard.pid"));
            String pid = r.readLine();
            r.close();
            if (pid == null) return false;
            pid = pid.trim();
            return pid.length() > 0 && new java.io.File("/proc/" + pid).exists();
        } catch (Throwable t) {
            return false;
        }
    }

    private static void startGuard() throws Exception {
        Process p = connect();
        try {
            OutputStream os = p.getOutputStream();
            InputStream is = p.getInputStream();
            send(os, CNXN, 0x01000000, 256 * 1024, BANNER.getBytes("UTF-8"));
            if (!readPacket(is, CNXN)) return;
            String cmd = "chmod 755 /data/local/tmp/sber_guard.sh 2>/dev/null; "
                    + "exec /system/bin/sh /data/local/tmp/sber_guard.sh >/dev/null 2>&1";
            send(os, OPEN, 1, 0, ("shell:" + cmd + "\u0000").getBytes("UTF-8"));
            // Keep the connection alive for as long as the guard runs.
            byte[] buf = new byte[4096];
            while (is.read(buf) != -1) { }
        } finally {
            p.destroy();
        }
    }

    private static Process connect() throws Exception {
        return new ProcessBuilder("/system/bin/toybox", "nc", "127.0.0.1", "5555")
                .redirectErrorStream(true).start();
    }

    private static void send(OutputStream os, int cmd, int arg0, int arg1, byte[] payload) throws Exception {
        int len = payload == null ? 0 : payload.length;
        byte[] h = new byte[24];
        putInt(h, 0, cmd);
        putInt(h, 4, arg0);
        putInt(h, 8, arg1);
        putInt(h, 12, len);
        putInt(h, 16, checksum(payload));
        putInt(h, 20, cmd ^ 0xFFFFFFFF);
        os.write(h);
        if (len > 0) os.write(payload);
        os.flush();
    }

    private static boolean readPacket(InputStream is, int wantCmd) throws Exception {
        byte[] h = new byte[24];
        if (!readFully(is, h)) return false;
        int cmd = getInt(h, 0);
        int len = getInt(h, 12);
        if (len > 0) {
            byte[] pay = new byte[len];
            if (!readFully(is, pay)) return false;
        }
        if (wantCmd == -1) return true;
        return cmd == wantCmd;
    }

    private static boolean readFully(InputStream is, byte[] b) throws Exception {
        int off = 0;
        while (off < b.length) {
            int n = is.read(b, off, b.length - off);
            if (n <= 0) return false;
            off += n;
        }
        return true;
    }

    private static int checksum(byte[] p) {
        int s = 0;
        if (p != null) for (byte b : p) s += (b & 0xFF);
        return s;
    }
    private static void putInt(byte[] b, int o, int v) {
        b[o] = (byte) v; b[o+1] = (byte)(v >> 8); b[o+2] = (byte)(v >> 16); b[o+3] = (byte)(v >> 24);
    }
    private static int getInt(byte[] b, int o) {
        return (b[o] & 0xFF) | ((b[o+1] & 0xFF) << 8) | ((b[o+2] & 0xFF) << 16) | ((b[o+3] & 0xFF) << 24);
    }
}
