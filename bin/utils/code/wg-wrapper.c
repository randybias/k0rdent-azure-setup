#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>

#define MAX_ARGS 10
#define MAX_ARG_LEN 256

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <command> [args...]\n", argv[0]);
        fprintf(stderr, "Commands: wg-show, wg-quick-up, wg-quick-down\n");
        return 1;
    }

    // Drop any supplementary groups
    if (setgroups(0, NULL) != 0) {
        perror("setgroups");
        return 1;
    }

    // Set real and effective UID/GID to root
    if (setgid(0) != 0) {
        perror("setgid");
        return 1;
    }
    if (setuid(0) != 0) {
        perror("setuid");
        return 1;
    }

    // Validate and execute commands
    if (strcmp(argv[1], "wg-show") == 0) {
        // wg show [interface]
        if (argc == 2) {
            execl("/opt/homebrew/bin/wg", "wg", "show", NULL);
        } else if (argc == 3) {
            execl("/opt/homebrew/bin/wg", "wg", "show", argv[2], NULL);
        } else {
            fprintf(stderr, "Invalid arguments for wg-show\n");
            return 1;
        }
    } else if (strcmp(argv[1], "wg-quick-up") == 0) {
        // wg-quick up <interface>
        if (argc != 3) {
            fprintf(stderr, "Usage: %s wg-quick-up <interface>\n", argv[0]);
            return 1;
        }
        execl("/opt/homebrew/bin/wg-quick", "wg-quick", "up", argv[2], NULL);
    } else if (strcmp(argv[1], "wg-quick-down") == 0) {
        // wg-quick down <interface>
        if (argc != 3) {
            fprintf(stderr, "Usage: %s wg-quick-down <interface>\n", argv[0]);
            return 1;
        }
        execl("/opt/homebrew/bin/wg-quick", "wg-quick", "down", argv[2], NULL);
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        fprintf(stderr, "Valid commands: wg-show, wg-quick-up, wg-quick-down\n");
        return 1;
    }

    // If we get here, execl failed
    perror("execl");
    return 1;
}