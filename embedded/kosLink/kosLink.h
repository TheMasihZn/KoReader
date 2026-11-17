/* kosLink: frame protocol between KOReader OS and small devices (ESP32, ATmega, any C compiler).
 * No malloc, no OS calls: 70 bytes of RAM for the parser. Same bytes as frontend/apps/kos/linkproto.lua.
 *
 *   0x7E | ver | type | seq | len | payload (0..64) | crc hi | crc lo
 *   CRC-16/CCITT-FALSE over ver..payload. Bytes 0x7E and 0x7D inside a frame go as 0x7D, byte ^ 0x20.
 *
 * Use:  kosLinkParser p; kosLinkInit(&p);
 *       on every received byte:  if (kosLinkFeed(&p, b, &frame)) { handle(frame.type, frame.payload, frame.len); }
 *       to send:  n = kosLinkEncode(KOSLINK_DATA, seq++, payload, 5, out, sizeof out); write(out, n);
 */
#ifndef KOSLINK_H
#define KOSLINK_H
#include <stdint.h>
#include <stddef.h>

#define KOSLINK_VER 1
#define KOSLINK_MAX 64
#define KOSLINK_HELLO 1
#define KOSLINK_DATA 2      /* payload: channel (1 byte), value int32 little endian, in thousandths */
#define KOSLINK_COMMAND 3
#define KOSLINK_ACK 4
#define KOSLINK_ERROR 5
#define KOSLINK_CHANNELS 6
/* worst case encoded size of a frame: every byte escaped */
#define KOSLINK_OUT_MAX (1 + 2 * (4 + KOSLINK_MAX + 2))

typedef struct { uint8_t type, seq, len; uint8_t payload[KOSLINK_MAX]; } kosLinkFrame;
typedef struct { uint8_t buf[4 + KOSLINK_MAX + 2]; uint8_t n; uint8_t escaped, in_frame; uint16_t errors; } kosLinkParser;

uint16_t kosLinkCrc16(const uint8_t *data, size_t len);
void kosLinkInit(kosLinkParser *p);
int kosLinkFeed(kosLinkParser *p, uint8_t byte, kosLinkFrame *out);  /* 1 = a frame is complete in *out */
size_t kosLinkEncode(uint8_t type, uint8_t seq, const uint8_t *payload, uint8_t len, uint8_t *out, size_t cap); /* 0 = does not fit */
void kosLinkPutData(uint8_t channel, int32_t milli, uint8_t payload[5]);
#endif
