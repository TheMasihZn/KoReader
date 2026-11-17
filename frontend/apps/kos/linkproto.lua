--[[--
kosLink frame protocol, the Lua side. The same bytes are produced and read by embedded/kosLink/kosLink.c
(ESP32, ATmega, anything with a C compiler). Frames are plain bytes, so any wire carries them: serial, TCP, Bluetooth.

    0x7E | ver | type | seq | len | payload (0..64) | crc hi | crc lo
    CRC is CRC-16/CCITT-FALSE (poly 0x1021, start 0xFFFF) over ver, type, seq, len and the payload.
    Inside a frame, bytes 0x7E and 0x7D are sent as 0x7D followed by the byte XOR 0x20.

Types: 1 hello (text name)  2 data (channel, int32 little endian, thousandths)  3 command (text)
       4 ack (seq of the frame acknowledged)  5 error (text)  6 channels (list of channel numbers)

    Link.encode(type, seq, payload) -> bytes (string)
    local p = Link.parser(); p:feed(bytes) -> list of { type, seq, payload } (bad frames are counted in p.errors)
    Link.dataPayload(channel, milli) / Link.readData(payload) -> channel, milli
]]

local Link = {}
Link.SOF, Link.ESC, Link.VER = 0x7E, 0x7D, 1
Link.HELLO, Link.DATA, Link.COMMAND, Link.ACK, Link.ERROR, Link.CHANNELS = 1, 2, 3, 4, 5, 6
Link.MAX = 64

function Link.crc16(bytes)
    local crc = 0xFFFF
    for i = 1, #bytes do
        crc = crc ~ (bytes:byte(i) << 8)
        for _ = 1, 8 do
            if crc & 0x8000 ~= 0 then crc = ((crc << 1) ~ 0x1021) & 0xFFFF else crc = (crc << 1) & 0xFFFF end
        end
    end
    return crc
end

local function stuff(s)
    return (s:gsub("[\x7E\x7D]", function(c) return "\x7D" .. string.char(c:byte() ~ 0x20) end))
end

function Link.encode(ftype, seq, payload)
    payload = payload or ""
    assert(#payload <= Link.MAX, "payload too long")
    local body = string.char(Link.VER, ftype, seq & 0xFF, #payload) .. payload
    local crc = Link.crc16(body)
    return "\x7E" .. stuff(body .. string.char(crc >> 8, crc & 0xFF))
end

function Link.dataPayload(channel, milli)
    return string.char(channel & 0xFF) .. string.pack("<i4", milli)
end

function Link.readData(payload)
    if #payload ~= 5 then return nil end
    return payload:byte(1), (string.unpack("<i4", payload, 2))
end

function Link.parser()
    local p = { buf = {}, escaped = false, inFrame = false, errors = 0 }
    function p:feed(bytes)
        local out = {}
        for i = 1, #bytes do
            local b = bytes:byte(i)
            if b == Link.SOF then
                if self.inFrame and #self.buf > 0 then self.errors = self.errors + 1 end
                self.buf, self.escaped, self.inFrame = {}, false, true
                goto continue
            end
            if not self.inFrame then goto continue end
            if b == Link.ESC then self.escaped = true; goto continue end
            if self.escaped then b = b ~ 0x20; self.escaped = false end
            self.buf[#self.buf + 1] = b
            -- complete when: ver,type,seq,len + len payload + 2 crc
            if #self.buf >= 4 then
                local len = self.buf[4]
                if len > Link.MAX then self.errors = self.errors + 1; self.inFrame = false
                elseif #self.buf == 4 + len + 2 then
                    local raw = string.char(table.unpack(self.buf, 1, 4 + len))
                    local crc = (self.buf[5 + len] << 8) | self.buf[6 + len]
                    if crc == Link.crc16(raw) and self.buf[1] == Link.VER then
                        out[#out + 1] = { type = self.buf[2], seq = self.buf[3], payload = raw:sub(5) }
                    else self.errors = self.errors + 1 end
                    self.inFrame = false
                end
            end
            ::continue::
        end
        return out
    end
    return p
end

return Link
