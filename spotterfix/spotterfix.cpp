// libspotterfix.so — настраивает родные споттеры Centaur:
// activation («Алиса») и command («стоп/хватит/пауза/громче/тише»).
//
// Штатный SpotterConfigurer в этой сборке не стартует, поэтому путь к
// моделям никто не задаёт: createActivationSpotter/createCommandSpotter
// пишут «Spotter path is empty». Здесь мы сами вызываем
// SpotterCapabilityProxy::setModelPaths на прокси из YandexIOSDK.
//
// Смещения — для libquasar_daemons.so из APK 4.16.1 (armeabi-v7a):
//   getSDKSingleton                          0x312db64
//   SpotterCapabilityProxy::setModelPaths    0x32cb360
//   SpotterCapabilityProxy::start            0x32cb7c0
//   YandexIOSDK::activationSpotterProxy_     +0xc8
//   YandexIOSDK::commandSpotterProxy_        +0xd0
//
// Командный прокси найден по совпадению vtable с activation-прокси
// и по строке remote_object_id = "CommandSpotterCapability" (field +0x28).
//
// Дополнительно: APK-ассет quasar.cfg должен содержать
// enableCommandSpotters=true, иначе capability распознаёт фразу, но
// отбрасывает её с «Command spotters disabled». Патч ассета —
// scripts/patch_centaur_command_spotter.sh.

#include <jni.h>
#include <android/log.h>
#include <cstdio>
#include <cstring>
#include <cstdint>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#include <string>
#include <map>
#include <thread>

namespace {

constexpr uintptr_t OFF_GET_SDK = 0x312db64;
constexpr uintptr_t OFF_SET_PATHS = 0x32cb360;
constexpr uintptr_t OFF_PROXY_START = 0x32cb7c0;
constexpr uintptr_t OFF_SDK_ACTIVATION_PROXY = 0xc8;
constexpr uintptr_t OFF_SDK_COMMAND_PROXY = 0xd0;

const char* kActivationDir =
    "/data/data/ru.yandex.quasar.centaur_app/files/system/spotter_models/activation/alisa";
const char* kCommandDir =
    "/data/data/ru.yandex.quasar.centaur_app/files/system/spotter_models/command";

const char* TAG = "SpotterFix";
const char* kLogPath =
    "/data/data/ru.yandex.quasar.centaur_app/files/data/daemons_logs/android_app.log";

uintptr_t module_base(const char* needle) {
    FILE* f = fopen("/proc/self/maps", "r");
    if (!f) return 0;
    char line[512];
    uintptr_t best = 0;
    while (fgets(line, sizeof(line), f)) {
        if (!strstr(line, needle)) continue;
        unsigned long start = 0, end = 0, off = 0;
        if (sscanf(line, "%lx-%lx %*s %lx", &start, &end, &off) == 3) {
            uintptr_t base = (uintptr_t)start - (uintptr_t)off;
            if (best == 0 || base < best) best = base;
        }
    }
    fclose(f);
    return best;
}

bool readable_range(uintptr_t addr, size_t len) {
    if (addr == 0) return false;
    FILE* f = fopen("/proc/self/maps", "r");
    if (!f) return false;
    char line[512];
    bool ok = false;
    while (fgets(line, sizeof(line), f)) {
        unsigned long start = 0, end = 0;
        char perms[8] = {0};
        if (sscanf(line, "%lx-%lx %7s", &start, &end, perms) == 3) {
            if (strchr(perms, 'r') && addr >= start && addr + len <= end) {
                ok = true;
                break;
            }
        }
    }
    fclose(f);
    return ok;
}

void ensure_activation_flags_file() {
    std::string flags = std::string(kActivationDir) + "/flags.txt";
    std::string multi = std::string(kActivationDir) + "/multiflags.txt";
    struct stat st;
    if (stat(flags.c_str(), &st) == 0) return;
    FILE* in = fopen(multi.c_str(), "rb");
    if (!in) return;
    FILE* out = fopen(flags.c_str(), "wb");
    if (!out) { fclose(in); return; }
    char buf[4096];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), in)) > 0) fwrite(buf, 1, n, out);
    fclose(in);
    fclose(out);
}

typedef void* (*GetSdkFn)();
typedef void (*SetPathsFn)(void*, const std::map<std::string, std::string>&);
typedef void (*ProxyStartFn)(void*);

// После диалога «Алисы» SDK штатно делает stopCommandSpotter. Повторный
// start, когда споттер уже работает, вызывает лишний stop/start и сбрасывает
// модель, поэтому start шлём только если последнее событие в логе — stop.
// Лог очень шумный (музыка/директивы), 128 КБ иногда не содержит stop;
// читаем хвост 4 МБ.
bool command_spotter_stopped() {
    FILE* f = fopen(kLogPath, "rb");
    if (!f) return true;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return true; }
    long sz = ftell(f);
    if (sz < 0) { fclose(f); return true; }
    long begin = sz > 4 * 1024 * 1024 ? sz - 4 * 1024 * 1024 : 0;
    if (fseek(f, begin, SEEK_SET) != 0) { fclose(f); return true; }
    std::string buf;
    buf.resize((size_t)(sz - begin));
    size_t n = fread(&buf[0], 1, buf.size(), f);
    fclose(f);
    buf.resize(n);
    size_t stop = buf.rfind("commandSpotter stopped");
    size_t start = buf.rfind("commandSpotter started");
    return stop != std::string::npos &&
           (start == std::string::npos || stop > start);
}

void worker() {
    uintptr_t base = 0;
    for (int i = 0; i < 600 && base == 0; ++i) {
        base = module_base("libquasar_daemons.so");
        if (!base) usleep(200 * 1000);
    }
    if (!base) {
        __android_log_print(ANDROID_LOG_ERROR, TAG, "libquasar_daemons.so not found");
        return;
    }

    auto get_sdk = (GetSdkFn)(base + OFF_GET_SDK);
    auto set_paths = (SetPathsFn)(base + OFF_SET_PATHS);
    auto proxy_start = (ProxyStartFn)(base + OFF_PROXY_START);

    bool first_start = true;
    bool last_need_start = false;
    int path_attempts = 0;

    for (;;) {
        ensure_activation_flags_file();
        if (void** sp = (void**)get_sdk()) {
            if (sp[0]) {
                uintptr_t sdk = (uintptr_t)sp[0];
                if (readable_range(sdk + OFF_SDK_COMMAND_PROXY, sizeof(uintptr_t))) {
                    uintptr_t activation = *(uintptr_t*)(sdk + OFF_SDK_ACTIVATION_PROXY);
                    uintptr_t command = *(uintptr_t*)(sdk + OFF_SDK_COMMAND_PROXY);
                    if (activation && command &&
                        readable_range(activation, sizeof(uintptr_t)) &&
                        readable_range(command, sizeof(uintptr_t))) {
                        // Прокси подключается не мгновенно; первые попытки
                        // могут уйти до handleRemotingConnect, поэтому 3 раза.
                        if (path_attempts < 3) {
                            std::map<std::string, std::string> activationPaths;
                            activationPaths["activation"] = kActivationDir;
                            set_paths((void*)activation, activationPaths);
                            std::map<std::string, std::string> commandPaths;
                            commandPaths["command"] = kCommandDir;
                            set_paths((void*)command, commandPaths);
                            ++path_attempts;
                            __android_log_print(ANDROID_LOG_INFO, TAG,
                                                "paths set (%d/3): activation=0x%lx command=0x%lx",
                                                path_attempts, (unsigned long)activation,
                                                (unsigned long)command);
                        }

                        bool need_start = first_start || command_spotter_stopped();
                        if (need_start) {
                            if (!last_need_start || first_start) {
                                __android_log_print(ANDROID_LOG_INFO, TAG,
                                                    "command spotter start: sdk=0x%lx command=0x%lx",
                                                    (unsigned long)sdk,
                                                    (unsigned long)command);
                            }
                            proxy_start((void*)command);
                            first_start = false;
                        }
                        last_need_start = need_start;
                    }
                }
            }
        }
        sleep(2);
    }
}

}  // namespace

extern "C" JNIEXPORT jint JNI_OnLoad(JavaVM*, void*) {
    std::thread(worker).detach();
    return JNI_VERSION_1_6;
}
