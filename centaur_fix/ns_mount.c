#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <unistd.h>

/*
 * Tiny helper for the SberPortal framework patch.
 *
 * adb shell can end up in a different mount namespace than init; enter init's
 * namespace first so the bind mounts are inherited by the next zygote.
 *
 * usage:
 *   centaur_ns_mount mount <source> <target>
 *   centaur_ns_mount umount <target>
 */
int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s mount|umount path [target]\n", argv[0]);
        return 2;
    }

    int fd = open("/proc/1/ns/mnt", O_RDONLY);
    if (fd < 0) {
        perror("open /proc/1/ns/mnt");
        return 1;
    }
    if (setns(fd, CLONE_NEWNS) != 0) {
        perror("setns");
        close(fd);
        return 1;
    }
    close(fd);

    if (strcmp(argv[1], "mount") == 0) {
        if (argc < 4) {
            fprintf(stderr, "usage: %s mount <source> <target>\n", argv[0]);
            return 2;
        }
        if (mount(argv[2], argv[3], NULL, MS_BIND, NULL) != 0) {
            perror("mount");
            return 1;
        }
        return 0;
    }

    if (strcmp(argv[1], "umount") == 0) {
        if (umount2(argv[2], MNT_DETACH) != 0 && errno != EINVAL && errno != ENOENT) {
            perror("umount2");
            return 1;
        }
        return 0;
    }

    fprintf(stderr, "unknown action: %s\n", argv[1]);
    return 2;
}
