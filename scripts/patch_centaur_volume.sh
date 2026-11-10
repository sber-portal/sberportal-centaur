#!/usr/bin/env bash
# Правки громкости в APK Centaur (SberPortal).
#
# Проблема: в этом APK `YandexIoServiceImpl.j()` начинается с `return-void`
# (в стоке там вызов `VolumeManager.register()`), поэтому нативный
# `volume_manager` не регистрируется:
#   - `sound_set_level` приходит от Алисы, но обработчика нет
#     ("Failed to find handler for directive");
#   - top sheet читает flow `g50/c.d()`, который никто не обновляет,
#     и показывает «звук отключён» при рабочей громкости.
#
# Что делает скрипт:
#   1. `j()` -> вызвать `VolumeManager.register()` (поле B) и выйти.
#      Остальное тело ж() не выполняем: там падение на null deviceID.
#   2. `a20/p$d.invokeSuspend` — `WindowManager.addView` в try/catch.
#      Иначе тост громкости падает с BadTokenException, когда activity
#      уже уничтожена (краш-луп при смене громкости).
#   3. Шкала громкости 0..10 (как в Sber), а не 0..16:
#      - `g50/c.a()` (getMaxVolume) -> 10;
#      - `g50/c.getVolume()` -> round(доля * 10);
#      - `g50/c.setVolume(int)` -> level / 10 (макс. 10 = системные 16);
#      - `g50/c$a.e(F)` -> reportVolume в логической шкале 0..10.
#
# Использование:
#   APKTOOL_DIR=/tmp/centaur_dec scripts/patch_centaur_volume.sh [output.apk]
#
# APKTOOL_DIR — проект apktool с распакованными classes4 (smali/).
set -euo pipefail

DIR="${APKTOOL_DIR:?set APKTOOL_DIR to an apktool project dir}"
OUT="${1:-centaur_volume.apk}"

python3 - "$DIR" <<'PY'
import sys, os

root = sys.argv[1]

# 1) YandexIoServiceImpl.j() -> register volume manager and return
p = os.path.join(root, 'smali/ru/yandex/quasar/centaur_app/YandexIoServiceImpl.smali')
s = open(p).read()
start = s.index('.method public final j()V')
end = s.index('.end method', start) + len('.end method')
body = '''.method public final j()V
    .locals 5

    iget-object v0, p0, Lru/yandex/quasar/centaur_app/YandexIoServiceImpl;->B:Lg50/a;

    if-eqz v0, :cond_vm

    invoke-virtual {v0}, Lru/yandex/io/sdk/jni/VolumeManager;->register()V

    :cond_vm
    return-void
.end method'''
s = s[:start] + body + s[end:]
open(p, 'w').write(s)
print('patched YandexIoServiceImpl.j()')

# 2) OverlayViewManager.addViewToWindow: catch BadTokenException
p = os.path.join(root, 'smali/a20/p$d.smali')
s = open(p).read()
old = '''    .line 28
    invoke-interface {p1, v1, v0}, Landroid/view/ViewManager;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V

    .line 29'''
new = '''    .line 28
    :try_start_0
    invoke-interface {p1, v1, v0}, Landroid/view/ViewManager;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
    :try_end_0
    .catch Ljava/lang/Exception; {:try_start_0 .. :try_end_0} :catch_0

    goto :goto_0

    :catch_0
    move-exception v0

    :goto_0
    .line 29'''
if old not in s:
    raise SystemExit('a20/p$d.smali: addView pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched OverlayViewManager addView (try/catch)')

# 3) volume scale 0..10
p = os.path.join(root, 'smali/g50/c.smali')
s = open(p).read()

start = s.index('.method public final a()I')
end = s.index('.end method', start) + len('.end method')
s = s[:start] + '''.method public final a()I
    .locals 1

    const/16 v0, 0xa

    return v0
.end method''' + s[end:]

start = s.index('.method public final getVolume()I')
end = s.index('.end method', start) + len('.end method')
s = s[:start] + '''.method public final getVolume()I
    .locals 2

    iget-object v0, p0, Lg50/c;->h:Lg50/c$a;

    invoke-virtual {v0}, Lg50/c$a;->d()F

    move-result v1

    const/high16 v0, 0x41200000    # 10.0f

    mul-float/2addr v1, v0

    invoke-static {v1}, Ljava/lang/Math;->round(F)I

    move-result v0

    return v0
.end method''' + s[end:]

old = '''    int-to-float p1, p1

    .line 47
    invoke-virtual {v0}, Ljava/lang/Float;->floatValue()F

    .line 48
    .line 49
    .line 50
    move-result v0

    .line 51
    div-float/2addr p1, v0
'''
new = '''    int-to-float p1, p1

    const/high16 v0, 0x41200000    # 10.0f

    div-float/2addr p1, v0
'''
if old not in s:
    raise SystemExit('g50/c.smali: setVolume pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched g50/c: max/getVolume/setVolume -> 0..10')

p = os.path.join(root, 'smali/g50/c$a.smali')
s = open(p).read()
old = 'invoke-virtual {v1, v0, v2}, Lru/yandex/io/sdk/jni/VolumeManager;->reportVolume(IZ)V'
new = '''int-to-float v4, v0

    const v3, 0x3f200000    # 0.625f (10/16)

    mul-float/2addr v4, v3

    invoke-static {v4}, Ljava/lang/Math;->round(F)I

    move-result v0

    invoke-virtual {v1, v0, v2}, Lru/yandex/io/sdk/jni/VolumeManager;->reportVolume(IZ)V'''
if s.count(old) != 1:
    raise SystemExit('g50/c$a.smali: reportVolume pattern not found')
s = s.replace(old, new, 1)
open(p, 'w').write(s)
print('patched reportVolume -> logical 0..10')
PY

cd "$(dirname "$DIR")"
apktool b "$(basename "$DIR")" -o "$OUT"

echo "Готово: $OUT"
echo "Дальше: zipalign -p -f 4 $OUT aligned.apk && apksigner sign ... aligned.apk"
