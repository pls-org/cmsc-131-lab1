<!--no-pdf-->
# CMSC 131 Lab 1 Starter
by pls-org

#### Members:  

[CMSC 131 LAB - Section 1]  

Lauricio, Justin B.  
Mok, Samantha F.  
Samaniego, Percie Louise Y.

## Design Notes

### Problem analysis

#### Encoder's Problem Analysis:
renpkt's encoder gets the field values from the struct made by `driver.c` and packs them into the 20-byte IPv4 header. The main problems are that some fields share the same byte, like `dscp` + `ecn` and `flags` + `fragment_offset`, the multi-byte fields need to be stored in big-endian, and the checksum needs to be calculated after the whole header is complete.

### Solution architecture

#### Encode Solution Architecture
`encode_header` in `encode.asm` gets the struct from `[ebp+8]` and the 20-byte header buffer from `[ebp+12]`. It uses the same offsets defined in `driver.c`.

The encoder is basically the reverse of the decoder. Instead of shifting and masking bits to get the field values, it shifts the values into the correct position and ORs them together.

##### Build Order  

1. **Byte 0:** `(version << 4) | ihl`
2. **Byte 1:** `(dscp << 2) | ecn`
3. **Bytes 2–3:** Store `total_length` high byte first.
4. **Bytes 4–5:** Store `identification` high byte first.
5. **Bytes 6–7:** Combine `flags` and `fragment_offset` into one 16-bit value, then split it into two bytes.
6. **Bytes 8–9:** Store `ttl` and `protocol`.
7. **Bytes 10–11:** Set these to zero first because this is where the checksum will go.
8. **Bytes 12–15:** Copy the source address (`src[0..3]`).
9. **Bytes 16–19:** Copy the destination address (`dst[0..3]`).
10. **Checksum:** Call `ip_checksum(hdr, 20)` and put the result into bytes 10–11 in big-endian.

The checksum has to be done last because it uses the entire header. All the other fields need to be written first.

### Timeline

One line per week. Name the subsystem each week finishes and the member
who owns it.

| Week | Goal | Owner |
|---|---|---|
| 1 |Designed the system, split subsystems, reviewed cdecl, and prototyped byte-0 decoding.| pls-org|
| 2 | | |
| 3 | | |
| 4 | Defense | |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem | Owner |
|---|---|
| Decode path (`decode.asm`) | Justin B. Lauricio |
| Encode path (`encode.asm`) | Percie Louise Y. Samaniego |
| Checksum and tests (`checksum.asm`, `tests/`) | Samantha F. Mok |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

- 

### Quirks

- 
