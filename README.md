<!--no-pdf-->

# CMSC 131 Lab 1 Starter

Decode, encode, and checksum 20-byte IPv4 packet headers under a C driver.
The manual is the assignment. This file is the repository's own notes.

## Layout

```text
Makefile            platform preamble and build rules
driver.c            provided: argument parsing and file I/O
cdecl.h             provided: the calling-convention macros
decode.asm          yours
encode.asm          yours
checksum.asm        yours
run_tests.sh        provided: the correctness gate
contract_test.c     provided: the second pass, in C
contract_regs.asm   provided: register discipline checks for contract_test
tests/              provided: the header fixtures, their expected output,
                    and manifest.txt, the list both passes read
LICENSE             CC BY-NC-SA 4.0, inherited from the pcasm material
```

## What to Run

```bash
make
make check
```

`make` builds `renpkt` and `contract_test`. `make check` builds both, then
runs `./run_tests.sh`, which reports each test and exits nonzero when any
of them differ.

The gate has two passes. The first decodes every header listed in
`tests/manifest.txt` and compares the output with `tests/expected/`. The
second is `contract_test`. It decodes and re-encodes every header the
manifest marks valid. It checks a checksum vector that needs the carry
folded twice. It checks that all three routines keep `ebx`, `esi`, `edi`,
and `ebp`, and return with `esp` where the call left it. A program can pass
the first pass and fail the second. That failure is the usual encoder bug.

## Reading a First Run

The assembly files ship as stubs that assemble and link as-is, so the build
works before you write any code. Right now they do nothing useful, which
makes every check fail: `7 of 7 checks differ`. That red run is the correct
starting state for a starter. The badge stays red until you implement the
routines.

## Adding a Header

Put the header in `tests/NAME.bin`. Write the output `renpkt --decode`
must print for it in `tests/expected/NAME.out`. Then add one line to
`tests/manifest.txt`:

```text
NAME valid
```

Use `invalid` for a header with a wrong checksum. A valid header joins the
round trip in `contract_test` as well as the decode pass. The gate fails
and names the file when a `.bin` is not in the manifest, and when a listed
header has no expected file.

## The Driver's Argument Checks

`renpkt --encode` refuses a value its field cannot hold, and two values the
standard forbids. `--len` takes 20 through 65535, because the total length
counts the header. It defaults to 20. `--flags` takes 0 through 3, because
the top bit of the field is reserved and must be zero. `--df` sets 2 and
`--mf` sets 1. A refused option exits with status 2 and writes no file.

## Documentation

The three sections at the end of this file are yours. Complete Design Notes
and Subsystem Ownership before the Week 1 progress report. Complete Quirks
and Issues before the Week 3 progress report. Each section says what it
needs. Leave the rest of this file as it is.

## Fixtures

The provided files are fixtures. The grader compares your fork against the
starter. An edit to `driver.c`, `Makefile`, `run_tests.sh`,
`contract_test.c`, `contract_regs.asm`, or a provided `tests/` file appears
as a diff in the open. Your own headers and manifest lines are additions,
not edits.

---

## Design Notes

### Problem analysis

renpkt's encoder gets the field values from the struct made by `driver.c` and packs them into the 20-byte IPv4 header. The main problems are that some fields share the same byte, like `dscp` + `ecn` and `flags` + `fragment_offset`, the multi-byte fields need to be stored in big-endian, and the checksum needs to be calculated after the whole header is complete.

`checksum.asm` and the `tests/` suite are responsible for verifying packet integrity and guaranteeing overall correctness.

The main problems for the checksum routine are:

- **Folding & One's Complement:** Summing ten 16-bit big-endian words into a 32-bit accumulator accumulates carries in the top 16 bits. These must be repeatedly folded back into the bottom 16 bits until the upper half is zero.
- **Endianness & Dual-Path Reuse:** The function must read raw 16-bit big-endian words without bugs and apply bitwise `NOT` at the end.
- **Register Preservation:** Standard x86 calling conventions require preserving `ebx`, `esi`, `edi`, and `ebp`.

The main problems for the test fixtures are:

- **Edge-Case Coverage:** Test cases must cover valid packets, invalid checksums, non-zero fragment offsets.
- **Test Suite Alignment:** Every binary fixture (`.bin`), expected output, and `manifest.txt` entry (`valid` vs `invalid`) must stay synchronized across both the decoding shell script pass and the C `contract_test` pass.

### Solution architecture

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

`ip_checksum` in `checksum.asm` takes the 20-byte header buffer from `[ebp+8]` and the length from `[ebp+12]` (which is 20) to use as a loop counter.

##### Computation Order

1. **Accumulator Setup:** The `eax` register is set to 0 to hold the running 32-bit total.
2. **Sum Loop:** A loop reads two bytes at a time, assembles them into 16-bit big-endian values, and adds them to `eax`. This is done until all bytes have been processed, with `eax` keeping any overflow safely in its upper 16 bits.
3. **Fold Loop:** A loop creates the one's complement sum. While the top half of `eax` (bits 16-31) has a value, it is shifted right and added back to the bottom half. This repeats until the top half is exactly 0.
4. **Bit Flip:** The `NOT` instruction is applied to `eax` so the bits can be flipped to take the final one's complement.
5. **Masking:** `eax` is masked with `0xFFFF` so the final result is a 16-bit value.
6. **Return:** The function returns this final number. It is up to the main program to check this return value.

### Timeline

One line per week. Name the subsystem each week finishes and the member
who owns it.

| Week | Goal                                                                                   | Owner   |
| ---- | -------------------------------------------------------------------------------------- | ------- |
| 1    | Designed the system, split subsystems, reviewed cdecl, and prototyped byte-0 decoding. | pls-org |
| 2    |                                                                                        |         |
| 3    |                                                                                        |         |
| 4    | Defense                                                                                |         |

## Subsystem Ownership

Complete this section before the Week 1 progress report. The manual lists
the three subsystems. Each member owns one. In a group of four, two members
share one. The commit history must agree with this table.

| Subsystem                                     | Owner                      |
| --------------------------------------------- | -------------------------- |
| Decode path (`decode.asm`)                    | Justin B. Lauricio         |
| Encode path (`encode.asm`)                    | Percie Louise Y. Samaniego |
| Checksum and tests (`checksum.asm`, `tests/`) | Samantha F. Mok            |

## Quirks and Issues

Complete this section before the Week 3 progress report. The syllabus asks
for documentation of quirks and issues with the complete implementation.
One entry per item. State what happens, what causes it, and what the group
did about it.

### Known issues

-

### Quirks

-
