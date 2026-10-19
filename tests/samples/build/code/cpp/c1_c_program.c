#include <stdio.h>
#include <stdlib.h>

int main(int argc, char *argv[]) {
    int *buf = malloc(sizeof(int) * 10);
    if (buf == NULL) {
        return 1;
    }
    printf("ok\n");
    free(buf);
    return 0;
}