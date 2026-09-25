### Problem analysis

**Input.** A raw 20-byte IPv4 base header — no options, no payload —
unpacked field by field into `struct ipv4_fields`.

**Output.** Decode writes nothing to a file — its output is a filled
`struct ipv4_fields`, handed back to `driver.c` for printing.

**Straightforward fields**

- Byte 0 splits into Version (bits 7–4) and IHL (bits 3–0)
- Byte 1 splits into DSCP (bits 7–2) and ECN (bits 1–0)
- Total Length (bytes 2–3) and Identification (bytes 4–5) are 16-bit
  big-endian values read straight across
- TTL (byte 8) and Protocol (byte 9) are single octets
- Header Checksum (bytes 10–11) is read the same way as any other 16-bit
  field — computing and *validating* it is the checksum subsystem's job,
  not decode's
- Source/Destination (bytes 12–19) are four raw octets each, no reordering

**The hard field**

Fragment Offset is the one genuinely hard case, and it's hard for two
independent reasons. First, bytes 6–7 together are a 16-bit big-endian
value, the same byte-order problem Total Length and Identification have —
byte 6 and byte 7 have to be combined in the right order before any shift
or mask means anything, and getting that order backwards scrambles every
bit position downstream. Second, once combined correctly, the 13-bit
Fragment Offset shares that word with the 3-bit Flags field, so pulling it
out means masking exactly 13 bits — get the width wrong and you either
lose bits or bleed into Flags next door. That's the case `sample05.bin` is
built to catch, and the one place decode can get either the byte order or
the mask width wrong and corrupt an adjacent field instead of failing
loudly.

**What decode doesn't validate**

Decode reads fields as-is, without enforcing the standard: it stores
whatever three flag bits and whatever IHL value the file holds (the driver
enforces the standard only on the encode side). Decode stores the raw IHL
value; the ×4 conversion for display (`IHL: 5 (20 bytes)`) happens in
`driver.c`'s `print_fields`, not in `decode.asm`.


### Solution architecture

**How the three routines split the work.** 

`decode_header` owns reading:
given a pointer to the 20-byte buffer and a pointer to `struct
ipv4_fields`, it fills every one of the thirteen members by masking,
shifting, and byte-swapping out of the buffer. 

Decode never calls `ip_checksum` at all. `driver.c`'s `cmd_decode` calls
`ip_checksum(hdr, 20)` directly on the raw buffer, outside `decode_header`
entirely, and reports `VALID` when the return is `0x0000` — the
one's-complement shortcut the manual describes. So the checksum member at
`+40` is, from decode's side, a fifth 16-bit field to store like any
other; decode's boundary with the checksum subsystem is narrower than it
first looks.

**Registers `decode_header` uses.** `esi` holds the buffer pointer (`hdr`,
`[ebp+8]`); `edi` holds the struct pointer (`out`, `[ebp+12]`). Both are
callee-saved, so the routine wraps its body in `pusha`/`popa` rather than
saving them individually — that also covers `ebx`, `eax`, `ecx`, and
`edx` for free. Because `pusha` saves `eax` along with everything else,
`mov eax, 0` has to come *after* `popa`, not before, or the return value
gets overwritten by whatever garbage `eax` held on entry. `eax`, `ecx`,
and `edx` are the scratch registers for the extraction itself — loading a
byte, masking it, shifting it into position — and since they're
caller-saved, nothing needs to preserve them beyond the routine's own use.

**Struct offsets**, from `driver.c`'s `ipv4_fields` (eleven 4-byte
`unsigned int` members, then two 4-byte `unsigned char` arrays, no
padding):

| Offset | Field | Offset | Field |
|---|---|---|---|
| +0 | version | +28 | fragment_offset |
| +4 | ihl | +32 | ttl |
| +8 | dscp | +36 | protocol |
| +12 | ecn | +40 | checksum |
| +16 | total_length | +44 | src[0..3] |
| +20 | identification | +48 | dst[0..3] |
| +24 | flags | | |

With the struct pointer in `edi`, a 32-bit field is a plain store —
`mov [edi+16], eax` for `total_length` — and each source/destination
octet is a single-byte store, `mov [edi+44], al` for the first byte of
`src`.