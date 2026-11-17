#include "kosLink.h"

uint16_t kosLinkCrc16(const uint8_t *d, size_t len) {
    uint16_t crc = 0xFFFF;
    while (len--) {
        crc ^= (uint16_t)(*d++) << 8;
        for (uint8_t i = 0; i < 8; i++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
    }
    return crc;
}

void kosLinkInit(kosLinkParser *p) { p->n = 0; p->escaped = 0; p->in_frame = 0; p->errors = 0; }

int kosLinkFeed(kosLinkParser *p, uint8_t b, kosLinkFrame *out) {
    if (b == 0x7E) { if (p->in_frame && p->n) p->errors++; p->n = 0; p->escaped = 0; p->in_frame = 1; return 0; }
    if (!p->in_frame) return 0;
    if (b == 0x7D) { p->escaped = 1; return 0; }
    if (p->escaped) { b ^= 0x20; p->escaped = 0; }
    if (p->n >= sizeof p->buf) { p->errors++; p->in_frame = 0; return 0; }
    p->buf[p->n++] = b;
    if (p->n >= 4) {
        uint8_t len = p->buf[3];
        if (len > KOSLINK_MAX) { p->errors++; p->in_frame = 0; return 0; }
        if (p->n == 4 + len + 2) {
            uint16_t crc = (uint16_t)((p->buf[4 + len] << 8) | p->buf[5 + len]);
            p->in_frame = 0;
            if (crc == kosLinkCrc16(p->buf, 4 + len) && p->buf[0] == KOSLINK_VER) {
                out->type = p->buf[1]; out->seq = p->buf[2]; out->len = len;
                for (uint8_t i = 0; i < len; i++) out->payload[i] = p->buf[4 + i];
                return 1;
            }
            p->errors++;
        }
    }
    return 0;
}

static int put(uint8_t b, uint8_t *out, size_t cap, size_t *n) {
    if (b == 0x7E || b == 0x7D) { if (*n + 2 > cap) return 0; out[(*n)++] = 0x7D; out[(*n)++] = b ^ 0x20; }
    else { if (*n + 1 > cap) return 0; out[(*n)++] = b; }
    return 1;
}

size_t kosLinkEncode(uint8_t type, uint8_t seq, const uint8_t *payload, uint8_t len, uint8_t *out, size_t cap) {
    if (len > KOSLINK_MAX || cap < 1) return 0;
    uint8_t body[4 + KOSLINK_MAX];
    body[0] = KOSLINK_VER; body[1] = type; body[2] = seq; body[3] = len;
    for (uint8_t i = 0; i < len; i++) body[4 + i] = payload[i];
    uint16_t crc = kosLinkCrc16(body, 4 + len);
    size_t n = 0;
    out[n++] = 0x7E;
    for (uint8_t i = 0; i < 4 + len; i++) if (!put(body[i], out, cap, &n)) return 0;
    if (!put((uint8_t)(crc >> 8), out, cap, &n) || !put((uint8_t)(crc & 0xFF), out, cap, &n)) return 0;
    return n;
}

void kosLinkPutData(uint8_t channel, int32_t milli, uint8_t p[5]) {
    p[0] = channel;
    p[1] = (uint8_t)(milli & 0xFF); p[2] = (uint8_t)((milli >> 8) & 0xFF);
    p[3] = (uint8_t)((milli >> 16) & 0xFF); p[4] = (uint8_t)((milli >> 24) & 0xFF);
}
