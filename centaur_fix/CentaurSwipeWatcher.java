import java.io.BufferedReader;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.RandomAccessFile;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;

/**
 * Root helper for Centaur on SberPortal.
 *
 * 1. BootSetup thread (runs once per boot, then every 30 s):
 *    - /dev/rtc0 -> 0666 (native Yandex IO SDK needs it)
 *    - /sdcard/Download/centaur_device_id (device_id из аккаунта Яндекса)
 *    - brightness 200, home = Centaur, free memory, start Centaur
 *    - STREAM_MUSIC = 13 (Sber VolumeRegulator likes to reset it to 3)
 * 2. Top-edge swipe -> open Centaur top sheet (original behaviour).
 *
 * Started by RavnBootStarter via a root shell on localhost adbd.
 */
public final class CentaurSwipeWatcher {
    private static final String LOG = "/data/local/tmp/centaur_watcher.log";
    // device_id из аккаунта Яндекса, под который выпущен private.pem.
    // Пусто = не перезаписывать существующий /sdcard/Download/centaur_device_id.
    private static final String DEVICE_ID = "";

    // Patched framework: PhoneWindowManager.sendSwipeRealizedBroadcast() NPE.
    // /system is read-only, so the patched oat files are bind-mounted into
    // init's mount namespace and system_server is restarted once per boot.
    private static final String FW_ODEX = "/system/framework/oat/arm/services.odex";
    private static final String FW_VDEX = "/system/framework/oat/arm/services.vdex";
    private static final String FW_ODEX_SRC = "/data/local/tmp/services_patched2.odex";
    private static final String FW_VDEX_SRC = "/data/local/tmp/services_patched.vdex";
    private static final String FW_MARK = "/data/local/tmp/centaur_fix_boot_id";
    private static final String FW_ENABLE = "/data/local/tmp/centaur_framework_patch.enable";
    private static final long FW_ODEX_OFF = 12608216L;
    private static final long FW_VDEX_OFF = 4936430L;
    private static final String FW_ODEX_PATCHED = "002b";
    private static final String FW_ODEX_ORIG = "adf5";
    private static final String FW_VDEX_PATCHED = "3806";
    private static final String FW_VDEX_ORIG = "6e10";

    private static long last = 0L;
    private static String pinnedPids = "";
    private static FileLock lock;

    public static void main(String[] args) throws Exception {
        RandomAccessFile raf = new RandomAccessFile("/data/local/tmp/centaur_watcher.lock", "rw");
        FileChannel ch = raf.getChannel();
        lock = ch.tryLock();
        if (lock == null) { log("already running"); return; }
        log("watcher start uid=" + android.os.Process.myUid());

        Thread boot = new Thread(new Runnable() {
            public void run() { bootSetup(); }
        }, "CentaurBootSetup");
        boot.setDaemon(true);
        boot.start();

        while (true) {
            try {
                try { exec(new String[]{"/system/bin/logcat", "-b", "system", "-c"}); } catch (Throwable t) { }
                ProcessBuilder pb = new ProcessBuilder("/system/bin/logcat", "-b", "system", "-v", "brief", "-s", "WindowManager:D");
                pb.redirectErrorStream(true);
                Process p = pb.start();
                log("logcat started");
                BufferedReader r = new BufferedReader(new InputStreamReader(p.getInputStream()));
                String line;
                while ((line = r.readLine()) != null) {
                    if (line.contains("sendSwipeRealizedBroadcast") && line.contains("SWIPE_GESTURE_TYPE: 2")) {
                        long now = System.currentTimeMillis();
                        if (now - last < 3000L) continue;
                        last = now;
                        log("swipe type2: " + line);
                        trigger();
                    }
                }
                log("logcat exited, restarting");
            } catch (Throwable t) {
                log("loop error " + t);
            }
            try { Thread.sleep(1000L); } catch (InterruptedException e) { }
        }
    }

    private static void bootSetup() {
        try {
            for (int i = 0; i < 180; i++) {
                if ("1".equals(out("/system/bin/getprop", "sys.boot_completed").trim())) break;
                Thread.sleep(2000L);
            }
            log("bootsetup start");
            String oldSysPid = out("/system/bin/pidof", "system_server").trim();
            if (ensureFrameworkPatch()) {
                // A framework restart can either kill this process (then
                // RavnBootStarter starts a fresh watcher) or leave this root
                // app_process alive.  Wait for the new system_server and
                // continue only in the latter case, so Pipka/guard/Centaur
                // setup is never skipped.
                log("framework restart issued; waiting for new system_server");
                boolean triedStart = false;
                boolean triedRecovery = false;
                boolean fwBack = false;
                for (int i = 0; i < 90; i++) {
                    Thread.sleep(2000L);
                    String p = out("/system/bin/pidof", "system_server").trim();
                    String b = out("/system/bin/getprop", "sys.boot_completed").trim();
                    if ("1".equals(b) && p.length() > 0 && !p.equals(oldSysPid)) {
                        fwBack = true;
                        break;
                    }
                    if (i == 15 && !triedStart) {
                        triedStart = true;
                        log("zygote not back after 30s; trying ctl.start zygote");
                        sh("setprop ctl.start zygote");
                    }
                    if (i == 30 && !triedRecovery) {
                        triedRecovery = true;
                        log("zygote still down; unmounting framework patch and disabling it");
                        String ns = "/data/local/tmp/centaur_ns_mount";
                        sh(ns + " umount " + FW_ODEX + " 2>/dev/null");
                        sh(ns + " umount " + FW_VDEX + " 2>/dev/null");
                        // Do not retry this patch on the next boot.
                        sh("mv " + FW_ODEX_SRC + " " + FW_ODEX_SRC + ".failed 2>/dev/null");
                        sh("mv " + FW_VDEX_SRC + " " + FW_VDEX_SRC + ".failed 2>/dev/null");
                        sh("rm -f " + FW_ENABLE);
                        sh("setprop ctl.start zygote");
                    }
                }
                if (fwBack) {
                    log("framework is back; continuing bootsetup");
                } else {
                    log("framework did not come back; bootsetup stops");
                    return;
                }
            }
            sh("chmod 666 /dev/rtc0 2>/dev/null");
            if (!DEVICE_ID.isEmpty()) {
                sh("mkdir -p /sdcard/Download; printf '%s\\n' " + DEVICE_ID + " > /sdcard/Download/centaur_device_id; chmod 644 /sdcard/Download/centaur_device_id");
            }
            sh("settings put system screen_brightness 200; settings put system screen_brightness_mode 0");
            // Home must not be Centaur's ChironSplashActivity: it destroys and
            // recreates MainActivity on every HOME, which is exactly the
            // multi-second empty screen before the top sheet. The proxy
            // resumes the existing MainActivity instead; keep the original
            // splash as a fallback when the proxy is not installed.
            sh("cmd package set-home-activity com.ravn.homeproxy/.HomeActivity || "
                    + "cmd package set-home-activity ru.yandex.quasar.centaur_app/.splash.ChironSplashActivity");
            // Free memory for the large Centaur native SDK before starting it.
            // On a watcher restart (for example after the Sber guard killed
            // StarOS and the cleanup killed this process) Centaur is usually
            // still alive; force-stopping it would visibly restart Alice for
            // no reason.
            sh("am force-stop ru.sberdevices.starlauncher");
            sh("am force-stop ru.sberdevices.starscreensaver");
            boolean centaurUp = out("/system/bin/pidof", "ru.yandex.quasar.centaur_app").trim().length() > 0;
            if (!centaurUp) {
                sh("am kill-all");
                Thread.sleep(2000L);
                sh("am force-stop ru.yandex.quasar.centaur_app");
                Thread.sleep(1000L);
            }
            sh("am start -n ru.yandex.quasar.centaur_app/.MainActivity");
            log("bootsetup started Centaur");
            Thread.sleep(2000L);
            pinCentaur();
            ensurePipkaPatch();

            while (true) {
                try {
                    if (!"666".equals(out("/system/bin/stat", "-c", "%a", "/dev/rtc0").trim())) {
                        sh("chmod 666 /dev/rtc0 2>/dev/null");
                    }
                    if (!DEVICE_ID.isEmpty() && !new java.io.File("/sdcard/Download/centaur_device_id").exists()) {
                        sh("mkdir -p /sdcard/Download; printf '%s\\n' " + DEVICE_ID + " > /sdcard/Download/centaur_device_id; chmod 644 /sdcard/Download/centaur_device_id");
                    }
                    if (out("/system/bin/pidof", "ru.yandex.quasar.centaur_app").trim().length() == 0) {
                        sh("am start -n ru.yandex.quasar.centaur_app/.MainActivity");
                    }
                    pinCentaur();
                    ensurePipkaPatch();
                    ensureSberGuard();
                } catch (Throwable t) {
                    log("bootsetup loop error " + t);
                }
                Thread.sleep(30000L);
            }
        } catch (Throwable t) {
            log("bootsetup failed " + t);
        }
    }

    private static void trigger() {
        long started = System.currentTimeMillis();
        try {
            exec(new String[]{"/system/bin/sh", "-c", "chmod 666 /dev/rtc0 2>/dev/null"});
            pinCentaur();
            // Sber's gesture service dispatches HOME synchronously before its
            // logcat line reaches us. HomeProxy resumes the existing
            // MainActivity in ~100-250 ms. Do not poll dumpsys here: each dump
            // takes 100-300 ms on this box and makes the drawer animation janky.
            boolean cold = out("/system/bin/pidof", "ru.yandex.quasar.centaur_app").trim().length() == 0;
            Thread.sleep(cold ? 900L : 250L);
            openTopSheet();
            if (cold) {
                // The first intent can be dropped while MainActivity is being
                // created (open_top_sheet is handled in onNewIntent, not
                // onCreate). Retry once after the activity is up.
                Thread.sleep(800L);
                openTopSheet();
            } else {
                // One cheap verification, not a 100 ms dumpsys loop: each dump
                // costs 100-300 ms in system_server and makes the animation
                // janky. Retry only when the drawer is really still closed.
                Thread.sleep(550L);
                if (!isTopSheetOpen()) {
                    log("sheet not open after 800ms, retrying");
                    openTopSheet();
                }
            }
            log("trigger done in " + (System.currentTimeMillis() - started) + "ms");
        } catch (Throwable t) {
            log("trigger error " + t);
        }
    }

    private static boolean isTopSheetOpen() {
        String dump = out("/system/bin/dumpsys", "activity", "top");
        int id = dump.indexOf("app:id/topSheetFragment");
        if (id < 0) return false;
        int start = dump.lastIndexOf('\n', id);
        int end = dump.indexOf('\n', id);
        String line = dump.substring(start < 0 ? 0 : start + 1, end < 0 ? dump.length() : end);
        java.util.regex.Matcher m = java.util.regex.Pattern
                .compile("(-?\\d+),(-?\\d+)-(\\d+),(-?\\d+) #7f0b04fe")
                .matcher(line);
        if (!m.find()) return false;
        try {
            return Integer.parseInt(m.group(2)) == 0 && Integer.parseInt(m.group(4)) > 100;
        } catch (NumberFormatException e) {
            return false;
        }
    }

    private static void openTopSheet() throws Exception {
        exec(new String[]{"/system/bin/am", "start", "-n",
                "ru.yandex.quasar.centaur_app/.MainActivity",
                "--ez", "open_top_sheet", "true"});
    }

    /**
     * Applies the selective PhoneWindowManager.sendSwipeRealizedBroadcast()
     * patch from /data/local/tmp.  The patched oat files only take effect in
     * system_server after a framework restart, so this runs at most once per
     * kernel boot (marker FW_MARK).  Returns true when a restart was issued.
     */
    private static boolean ensureFrameworkPatch() {
        try {
            if (!new java.io.File(FW_ENABLE).exists()) {
                log("framework patch disabled (no " + FW_ENABLE + ")");
                return false;
            }
            java.io.File srcO = new java.io.File(FW_ODEX_SRC);
            java.io.File srcV = new java.io.File(FW_VDEX_SRC);
            java.io.File helper = new java.io.File("/data/local/tmp/centaur_ns_mount");
            if (!srcO.exists() || !srcV.exists() || !helper.exists()) {
                log("framework patch files missing");
                return false;
            }
            String liveO = "/proc/1/root" + FW_ODEX;
            String liveV = "/proc/1/root" + FW_VDEX;
            long tO = fileSize(liveO);
            long tV = fileSize(liveV);
            if (tO <= 0 || tV <= 0 || tO != srcO.length() || tV != srcV.length()) {
                log("framework version mismatch: target=" + tO + "/" + tV
                        + " patch=" + srcO.length() + "/" + srcV.length());
                return false;
            }

            // Refuse to mount a patch built for another framework build: the
            // bytes at the patch offsets must be either the known original or
            // the known patched pair.
            boolean knownO = checkPatchByte(liveO, FW_ODEX_OFF, FW_ODEX_PATCHED)
                    || checkPatchByte(liveO, FW_ODEX_OFF, FW_ODEX_ORIG);
            boolean knownV = checkPatchByte(liveV, FW_VDEX_OFF, FW_VDEX_PATCHED)
                    || checkPatchByte(liveV, FW_VDEX_OFF, FW_VDEX_ORIG);
            if (!knownO || !knownV) {
                log("unknown framework build; refusing to mount patched files");
                return false;
            }

            boolean patched = checkPatchByte(liveO, FW_ODEX_OFF, FW_ODEX_PATCHED)
                    && checkPatchByte(liveV, FW_VDEX_OFF, FW_VDEX_PATCHED);
            if (!patched) {
                mountFramework(helper.getAbsolutePath(), FW_ODEX_SRC, FW_ODEX);
                mountFramework(helper.getAbsolutePath(), FW_VDEX_SRC, FW_VDEX);
                Thread.sleep(500L);
                patched = checkPatchByte(liveO, FW_ODEX_OFF, FW_ODEX_PATCHED)
                        && checkPatchByte(liveV, FW_VDEX_OFF, FW_VDEX_PATCHED);
                if (!patched) {
                    mountFramework(helper.getAbsolutePath(), FW_ODEX_SRC, FW_ODEX);
                    mountFramework(helper.getAbsolutePath(), FW_VDEX_SRC, FW_VDEX);
                    Thread.sleep(500L);
                    patched = checkPatchByte(liveO, FW_ODEX_OFF, FW_ODEX_PATCHED)
                            && checkPatchByte(liveV, FW_VDEX_OFF, FW_VDEX_PATCHED);
                }
                if (!patched) {
                    log("framework patch mount failed");
                    return false;
                }
                log("framework patch mounted");
            }

            String bootId = out("/system/bin/cat", "/proc/sys/kernel/random/boot_id").trim();
            String mark = readText(FW_MARK).trim();
            if (bootId.length() > 0 && !bootId.equals(mark)) {
                // PackageManager rescans /vendor on a framework restart.  If
                // the Pipka-patched APK is bind-mounted at that moment, PM can
                // drop ru.sberdevices.services as "unknown" (the patched APK
                // is not the signed system package).  Unmount it first; the
                // regular bootsetup remounts it after the restart.
                String pipka = "/vendor/priv-app/StarDroidStarServices/StarDroidStarServices.apk";
                if (out("/system/bin/cat", "/proc/1/mounts").contains(pipka)) {
                    sh(helper.getAbsolutePath() + " umount " + pipka);
                    log("pipka unmounted for framework restart");
                }
                writeText(FW_MARK, bootId);
                log("waiting 30s for boot to settle before zygote restart");
                Thread.sleep(30000L);
                log("restarting zygote to load patch (boot " + bootId + ")");
                // Restarting only zygote/system_server is much safer than
                // `stop; start` on a freshly booted device: init and this root
                // watcher stay alive, and the new system_server still inherits
                // init's bind mounts.
                sh("setprop ctl.restart zygote");
                return true;
            }
            return false;
        } catch (Throwable t) {
            log("framework patch error " + t);
            return false;
        }
    }

    private static void mountFramework(String helper, String src, String dst) {
        sh(helper + " umount " + dst + " 2>/dev/null");
        sh(helper + " mount " + src + " " + dst);
    }

    private static long fileSize(String path) {
        String s = out("/system/bin/stat", "-c", "%s", path).trim();
        try {
            return Long.parseLong(s);
        } catch (Throwable t) {
            return -1L;
        }
    }

    private static boolean checkPatchByte(String path, long off, String want) {
        RandomAccessFile f = null;
        try {
            f = new RandomAccessFile(path, "r");
            f.seek(off);
            int a = f.read();
            int b = f.read();
            if (a < 0 || b < 0) return false;
            return String.format("%02x%02x", a, b).equals(want);
        } catch (Throwable t) {
            return false;
        } finally {
            try { if (f != null) f.close(); } catch (Throwable t) { }
        }
    }

    private static String readText(String path) {
        RandomAccessFile f = null;
        try {
            f = new RandomAccessFile(path, "r");
            byte[] b = new byte[(int) Math.min(f.length(), 256L)];
            f.readFully(b);
            return new String(b, "UTF-8");
        } catch (Throwable t) {
            return "";
        } finally {
            try { if (f != null) f.close(); } catch (Throwable t) { }
        }
    }

    private static void writeText(String path, String s) {
        try {
            FileOutputStream fos = new FileOutputStream(path, false);
            fos.write(s.getBytes("UTF-8"));
            fos.close();
        } catch (Throwable t) {
            log("write " + path + " failed: " + t);
        }
    }

    /**
     * Sber draws the white Pipka pill over every app except its own launcher.
     * The patched vendor APK adds Centaur/HomeProxy to that allowlist, so
     * GestureNavigationImpl calls setVisibility(GONE).  /vendor is read-only:
     * bind-mount the patched APK from /data and restart the service once.
     */
    private static void ensurePipkaPatch() {
        String src = "/data/local/tmp/StarDroidStarServices_patched.apk";
        String dst = "/vendor/priv-app/StarDroidStarServices/StarDroidStarServices.apk";
        String helper = "/data/local/tmp/centaur_ns_mount";
        try {
            if (!new java.io.File(src).exists() || !new java.io.File(helper).exists()) {
                log("pipka patch files missing");
                return;
            }
            if (out("/system/bin/cat", "/proc/1/mounts").contains(dst)) return;
            sh(helper + " mount " + src + " " + dst);
            if (!out("/system/bin/cat", "/proc/1/mounts").contains(dst)) {
                log("pipka patch mount failed");
                return;
            }
            log("pipka patch mounted");
            // The running service still has the old classes loaded; a restart
            // makes it pick up the bind-mounted dex.  Do not use force-stop:
            // it marks the package stopped and StarOS will not bring it back.
            sh("kill -9 $(pidof ru.sberdevices.services) 2>/dev/null");
            Thread.sleep(2000L);
        } catch (Throwable t) {
            log("pipka patch error " + t);
        }
    }

    /**
     * Keep the stock Sber assistant silent.  ru.sberdevices.services runs its
     * own always-on spotter and restores the stock "salut"/"sber" model after
     * updates, so the model cannot simply be replaced once.  The guard script
     * watches spotter.log and kills the service on activation.
     */
    private static void ensureSberGuard() {
        try {
            String pid = out("/system/bin/cat", "/data/local/tmp/sber_guard.pid").trim();
            if (pid.length() > 0 && new java.io.File("/proc/" + pid).exists()) {
                return;
            }
            if (!new java.io.File("/data/local/tmp/sber_guard.sh").exists()) {
                log("sber guard script missing");
                return;
            }
            sh("chmod 755 /data/local/tmp/sber_guard.sh 2>/dev/null");
            sh("setsid /system/bin/sh /data/local/tmp/sber_guard.sh "
                    + ">/dev/null 2>&1 </dev/null &");
            Thread.sleep(300L);
            log("sber guard started pid="
                    + out("/system/bin/cat", "/data/local/tmp/sber_guard.pid").trim());
        } catch (Throwable t) {
            log("sber guard error " + t);
        }
    }

    /**
     * Keep the Centaur process resident. Otherwise launching any other app
     * makes LMK kill it; on the next swipe it cold-starts, the cached top-sheet
     * Div is gone, and the user sees an empty drawer for several seconds while
     * the Div is fetched again.
     */
    private static void pinCentaur() {
        String pids = out("/system/bin/pidof", "ru.yandex.quasar.centaur_app").trim();
        if (pids.length() == 0) return;
        for (String pid : pids.split("\\s+")) {
            try {
                FileOutputStream fos = new FileOutputStream("/proc/" + pid + "/oom_score_adj");
                fos.write("-1000".getBytes("UTF-8"));
                fos.close();
            } catch (Throwable t) {
                log("pin " + pid + " failed: " + t);
            }
        }
        if (!pids.equals(pinnedPids)) {
            pinnedPids = pids;
            log("pinned centaur pid=" + pids);
        }
    }

    private static void sh(String cmd) {
        try {
            exec(new String[]{"/system/bin/sh", "-c", cmd});
        } catch (Throwable t) {
            log("sh error: " + cmd + " -> " + t);
        }
    }

    private static String out(String... cmd) {
        try {
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process p = pb.start();
            InputStream is = p.getInputStream();
            StringBuilder sb = new StringBuilder();
            byte[] buf = new byte[4096];
            int n;
            while ((n = is.read(buf)) != -1) sb.append(new String(buf, 0, n, "UTF-8"));
            p.waitFor();
            return sb.toString();
        } catch (Throwable t) {
            return "";
        }
    }

    private static void exec(String[] cmd) throws Exception {
        ProcessBuilder pb = new ProcessBuilder(cmd);
        pb.redirectErrorStream(true);
        Process p = pb.start();
        InputStream is = p.getInputStream();
        byte[] buf = new byte[4096];
        while (is.read(buf) != -1) { }
        p.waitFor();
    }

    private static synchronized void log(String s) {
        try {
            FileOutputStream fos = new FileOutputStream(LOG, true);
            java.text.SimpleDateFormat f = new java.text.SimpleDateFormat("MM-dd HH:mm:ss.SSS");
            fos.write((f.format(new java.util.Date()) + " " + s + "\n").getBytes("UTF-8"));
            fos.close();
        } catch (Throwable t) { }
    }
}
