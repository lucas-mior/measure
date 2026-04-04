#include <time.h>
#include <sys/wait.h>

#include "util.c"

int main(int argc, char **argv) {
    char command[BUFSIZ];
    struct timespec t0;
    struct timespec t1;

    if (argc < 2) {
        error("usage: %s program [arguments...]\n", argv[0]);
        exit(EXIT_FAILURE);
    }

    STRING_FROM_ARRAY(command, " ", &argv[1], argc - 1);

    clock_gettime(CLOCK_MONOTONIC_RAW, &t0);

    switch (fork()) {
    case -1:
        error("Error forking: %s.\n", strerror(errno));
        exit(EXIT_FAILURE);
    case 0:
        execvp(argv[1], &argv[1]);

        error("Error executing:\n\n"
              RED("%s\n")
              "%s.\n", command, strerror(errno));
        exit(EXIT_FAILURE);
    default:
        if (wait(NULL) < 0) {
            error("Error waiting for child: %s.\n", strerror(errno));
            exit(EXIT_FAILURE);
        }
    }

    clock_gettime(CLOCK_MONOTONIC_RAW, &t1);

    {
        llong seconds = t1.tv_sec - t0.tv_sec;
        llong nanos = t1.tv_nsec - t0.tv_nsec;
        double total_seconds = (double)seconds + (double)nanos / 1.0e9;

        printf("\nTiming for command:\n\n"
               BLUE("%s\n")
               "    "BLUE("%f")"s\n", command, total_seconds);
    }
    exit(EXIT_SUCCESS);
}
