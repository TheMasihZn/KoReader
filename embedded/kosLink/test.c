/* Test tool: `./kosLinkTest enc type seq hexpayload` prints the frame in hex; `./kosLinkTest dec hexframe` prints type seq hexpayload or BAD. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "kosLink.h"
static int hex(const char *s, uint8_t *o) { int n = 0; while (s[0] && s[1]) { unsigned v; sscanf(s, "%2x", &v); o[n++] = (uint8_t)v; s += 2; } return n; }
int main(int argc, char **argv) {
    uint8_t buf[256], out[KOSLINK_OUT_MAX];
    if (argc >= 5 && !strcmp(argv[1], "enc")) {
        int n = hex(argv[4], buf);
        size_t m = kosLinkEncode((uint8_t)atoi(argv[2]), (uint8_t)atoi(argv[3]), buf, (uint8_t)n, out, sizeof out);
        for (size_t i = 0; i < m; i++) printf("%02x", out[i]);
        printf("\n"); return 0;
    }
    if (argc >= 3 && !strcmp(argv[1], "dec")) {
        int n = hex(argv[2], buf); kosLinkParser p; kosLinkFrame f; kosLinkInit(&p); int got = 0;
        for (int i = 0; i < n; i++) if (kosLinkFeed(&p, buf[i], &f)) { got = 1; printf("%d %d ", f.type, f.seq); for (int k = 0; k < f.len; k++) printf("%02x", f.payload[k]); printf("\n"); }
        if (!got) { printf("BAD\n"); }
        return 0;
    }
    return 1;
}
