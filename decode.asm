;
; decode.asm - extract every field from a 20-byte IPv4 header.
;
; This is your starting point. It assembles and links as-is, so the build
; works before you write any code. Right now it stores nothing, so renpkt
; prints the zeros driver.c put in the struct. Your job is to replace that
; with the extraction described below.
;
; The contract, from driver.c:
;
;       struct ipv4_fields *out   [ebp+12]
;       unsigned char *hdr        [ebp+8]
;
; hdr points at twenty bytes in network byte order. out points at the struct
; documented in driver.c. Its offsets are:
;
;   +0 version   +4 ihl    +8 dscp   +12 ecn   +16 total_length
;   +20 identification    +24 flags  +28 fragment_offset
;   +32 ttl      +36 protocol       +40 checksum
;   +44 src[0..3]                   +48 dst[0..3]
;
; Every int member is 4 bytes, so a plain 32-bit store fills one. The
; addresses are four single-byte stores each.
;
; Do not clobber ebx, esi, edi, or ebp. C assumes they survive your call.
; Return in eax (driver.c ignores it here, so returning 0 is fine).
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _decode_header decode_header
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _decode_header
_decode_header:
        enter   0,0
        pusha

        ;
        ; TODO: read the header and fill the struct.
        ;
        ; The field-by-field layout is the table in the manual. The notes
        ; that matter before you start:
        ;
        ;   * Every multi-byte field is big-endian, so load it byte by byte
        ;     and recombine. A single 16-bit load gives you the bytes
        ;     reversed.
        ;   * The fragment offset straddles a byte boundary. Its top five
        ;     bits live in byte 6 and its bottom eight in byte 7. Combine
        ;     both bytes into one word first, then shift and mask.
        ;   * The flags are the top three bits of the same word.
        ;   * Read and store the checksum field like any other field.
        ;     ip_checksum computes the VALID line separately.
        ;   * src and dst are four single-byte stores each. No shifting.
        ;
        ; Nothing here reads the file or prints. This routine only fills
        ; the struct, and driver.c does the rest.
        ;

        mov     esi, [ebp + 8]  ;esi <- hdr
        mov     edi, [ebp + 12] ; edi <- out

        movzx   eax, byte [esi] ; eax <- byte 0   prepends byte with zeroes 
        mov     ecx, eax        ; ecx <- eax <- byte 0 

        ; --------- BYTE 0 ----------------------------------------
        ; extracting the version (bits 7 - 4)
        shr     ecx, 4
        and     ecx, 0x0F       ; mask ecx to extract the nibble
        mov     [edi + 0], ecx  ; out -> version

        ; extracting the IHL (bit 3 - 0) 
        mov     edx, eax
        and     edx, 0x0F 
        mov     [edi + 4], edx

        ; ---------- BYTE 1 ----------------------------------------------------
        movzx   eax, byte [esi + 1]     ; eax <- byte 1 (prepends byte with 0s)
        mov     ecx, eax                ; ecx <- eax <- byte 1

        ; extracting dscp (bits 7 - 2)
        shr     ecx, 2                  ; bits 7-2 -> bits 5-0
        and     ecx, 0x3F               ; mask to extract the 6 bits
        mov     [edi + 8], ecx          ; out -> dscp

        ; extracting ecn (bits 1 - 0)
        mov     edx, eax
        and     edx, 0x03               ; mast to extract the 2 bits
        mov     [edi + 12], edx         ; out -> ecn


        ; ------------- BYTES 2-3 (total_length) -----------------------------
        movzx   eax, byte [esi + 2]     ; eax <- byte 2 (high byte)
        shl     eax, 8                  ; shift left 8 to make room for low byte

        movzx   ecx, byte [esi + 3]     ; ecx <- byte 3 (low byte)
        or      eax, ecx                ; eax <- combined 16-bit value
        mov     [edi + 16], eax         ; out -> total_length

        ; ------------- BYTES 4-5 (identification) ---------------------------
        movzx   eax, byte [esi + 4]     ; eax <- byte 4 (high byte)
        shl     eax, 8                  ; shift left 8 to make room for low byte
        movzx   ecx, byte [esi + 5]     ; ecx <- byte 5 (low byte)
        or      eax, ecx                ; eax <- combined 16-bit value
        mov     [edi + 20], eax         ; out -> identification

        ; ----------- BYTE 6-7 (flags + fragment_offset) ----------------------

        ; split byte-by-byte, because the 13-bit field straddles both bytes.
        ; recombine first
        movzx   eax, byte [esi + 6]    ; eax <- byte 6 (high byte)
        shl     eax, 8
        movzx   ecx, byte [esi + 7]    ; ecx <- byte 7 (low byte)
        or      eax, ecx               ; eax <- combined 16-bit word

        ; extracting flags (bits 15 - 13 of the word)
        mov     ecx, eax
        shr     ecx, 13                ; bits 15-13 -> bits 2-0
        and     ecx, 0x07              ; mask to extract the 3 bits
        mov     [edi + 24], ecx        ; out -> flags

        ; extracting fragment_offset (bits 12 - 0 of the word)
        mov     edx, eax
        and     edx, 0x1FFF            ; mask to extract the 13 bits
        mov     [edi + 28], edx        ; out -> fragment_offset

        ; ----------------- BYTE 8 (ttl) ---------------------------------
        movzx   eax, byte [esi + 8]    ; eax <- byte 8
        mov     [edi + 32], eax        ; out -> ttl

        ; ----------------- BYTE 9 (protocol) ---------------------------------
        movzx  eax, byte [esi + 9]     ; eax <- byte 9
        mov    [edi + 36], eax         ; out -> protocol

        ; ----------------- BYTE 10 - 11 (checksum) ------------------------
        ; recombination of byte 10 and 11
        movzx   eax, byte [esi + 10]    ; eax <- byte 10
        shl     eax, 8                  ; shift left to accomodate byte 11
        movzx   ecx, byte [esi + 11]    ; ecx <- byte 11
        or      eax, ecx                ; eax <- 16-bit combination word
        mov     [edi + 40], eax         ; out -> checksum

        ; ----------------- BYTE 12 - 15 (src) -----------------------------
        ; four independent octets, no recombination
        movzx   eax, byte [esi + 12]    ; eax <- byte 12
        mov     [edi + 44], al           

        movzx   eax, byte [esi + 13]    ; eax <- byte 13
        mov     [edi + 45], al   

        movzx   eax, byte [esi + 14]    ; eax <- byte 14
        mov     [edi + 46], al   

        movzx   eax, byte [esi + 15]    ; eax <- byte 15
        mov     [edi + 47], al   

        ; ----------------- BYTE 16 - 19 (src) -----------------------------
        ; four independent octets, no recombination
        movzx   eax, byte [esi + 16]    ; eax <- byte 16
        mov     [edi + 48], al           

        movzx   eax, byte [esi + 17]    ; eax <- byte 17
        mov     [edi + 49], al   

        movzx   eax, byte [esi + 18]    ; eax <- byte 18
        mov     [edi + 50], al   

        movzx   eax, byte [esi + 19]    ; eax <- byte 19
        mov     [edi + 51], al   

        popa
        mov     eax, 0
        leave
        ret
