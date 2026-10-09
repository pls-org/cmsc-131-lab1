;
; encode.asm - build a 20-byte IPv4 header from the field struct.
;
; This is your starting point. It assembles and links as-is, so the build
; works before you write any code. Right now it writes nothing, so the
; twenty bytes driver.c saves are whatever the buffer held. Your job is to
; replace that with the construction described below.
;
; * where arguments came from
; The contract, from driver.c:
;
;       unsigned char *hdr        [ebp+12]
;       struct ipv4_fields *in    [ebp+8]
;
; * driver.c documents the struct layout:
;
;   +0 version   +4 ihl    +8 dscp   +12 ecn   +16 total_length
;   +20 identification    +24 flags  +28 fragment_offset
;   +32 ttl      +36 protocol       +40 checksum
;   +44 src[0..3]                   +48 dst[0..3]
;
; * big endian req
; You write twenty bytes into hdr. Every multi-byte field goes out
; big-endian: the high byte first. The fragment offset's top five bits share
; byte 6 with the three flag bits. Its bottom eight bits are byte 7.
;
; * checksum is last & zero is fist
; The checksum is your job too. Bytes 10-11 must read as zero while the
; checksum is computed. Write them as zero, call ip_checksum over the
; finished header, and store its result into the field. The struct's
; checksum member is read on the decode path only. Don't copy it here.
;
; *cdecl obligations
;
; *Do not clobber ebx, esi, edi, or ebp. 
; C assumes they survive your call.
; Return in eax (driver.c ignores it here, so returning 0 is fine).
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _ip_checksum ip_checksum
  %define _encode_header encode_header
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

extern _ip_checksum

segment .text
        global  _encode_header
_encode_header:
        enter   0,0
        pusha

        ;
        ; TODO: build the header from the struct.
        ;
        ; This is the reverse of decode. Mask each field to its width,
        ; shift it up to where it lives, or the pieces of a shared byte
        ; together, then store the byte. The fields that do not straddle
        ; anything are one store each.
        ;
        ; The checksum comes last, after every other byte is written. Write
        ; bytes 10-11 as zero, call ip_checksum with the header and 20, and
        ; store its result (in ax) into the field big-endian. Computing it
        ; before the rest of the header is in place sums whatever garbage
        ; was in the buffer. ip_checksum preserves ebx, esi, edi, and ebp,
        ; so a pointer kept in one of those survives the call. eax, ecx, and
        ; edx do not.
        ;

        mov     esi, [ebp+8]            ; esi = struct ipv4_fields *in
        mov     edi, [ebp+12]           ; edi = unsigned char *hdr


        ; byte 0: (version << 4) | ihl
        ; shift the 4-bit version to the left, glue the 4-bit ihl to the right
        mov     eax, [esi+0]            ; get version
        and     eax, 0Fh                ; keep 4 bits
        shl     eax, 4                  ; move to upper 4 bits
        mov     ecx, [esi+4]            ; get IHL
        and     ecx, 0Fh                ; keep 4 bits
        or      eax, ecx                ; combine version + IHL
        mov     [edi+0], al             ; store byte 0


        ; byte 1: (dscp << 2) | ecn
        ; shift the 6-bit dscp to the left, glue the 2-bit ecn to the right
        mov     eax, [esi+8]            ; get DSCP
        and     eax, 3Fh                ; keep 6 bits
        shl     eax, 2                  ; move to upper 6 bits
        mov     ecx, [esi+12]           ; get ECN
        and     ecx, 03h                ; keep 2 bits
        or      eax, ecx                ; combine DSCP + ECN - to form 1 byte
        mov     [edi+1], al             ; store byte 1


        ; bytes 2-3: total_length, big-endian
        ; network order needs the high byte first, low byte second
        mov     eax, [esi+16]           ; get total length
        mov     [edi+3], al             ; store low byte
        mov     [edi+2], ah             ; store high byte


        ; bytes 4-5: identification, big-endian
        mov     eax, [esi+20]           ; get identification
        mov     [edi+5], al             ; store low byte
        mov     [edi+4], ah             ; store high byte


        ; bytes 6-7: (flags << 13) | (fragment_offset & 0x1FFF)
        ; push 3-bit flags to the very top, glue the 13-bit offset below it
        mov     eax, [esi+24]           ; get flags
        and     eax, 07h                ; keep 3 bits
        shl     eax, 13                 ; move flags to upper bits
        mov     ecx, [esi+28]           ; get fragment offset
        and     ecx, 1FFFh              ; keep 13 bits
        or      eax, ecx                ; combine flags + offset
        mov     [edi+7], al             ; store low byte
        mov     [edi+6], ah             ; store high byte


        ; byte 8: ttl, byte 9: protocol
        ; these are exactly 1 byte each, so drop them straight in
        mov     eax, [esi+32]           ; get TTL
        mov     [edi+8], al             ; store byte 8
        mov     eax, [esi+36]           ; get protocol
        mov     [edi+9], al             ; store byte 9


        ; bytes 10-11: zero before computing the checksum
        ; must be completely blank before we do the checksum math
        mov     byte [edi+10], 0        ; clear checksum high byte
        mov     byte [edi+11], 0        ; clear checksum low byte       


        ; bytes 12-15 src, 16-19 dst (already in wire order)
        ; just copy all 4 bytes of the IP addresses directly
        mov     eax, [esi+44]           ; get source address
        mov     [edi+12], eax           ; store source address
        mov     eax, [esi+48]           ; get destination address
        mov     [edi+16], eax           ; store destination address


        ; checksum last: ip_checksum(hdr, 20)
        ; header is fully built now, calculate the sum and fill bytes 10-11
        push    dword 20                ; pass header length
        push    edi                     ; pass header address
        call    _ip_checksum            ; calculate checksum
        add     esp, 8                  ; clean arguments
        mov     [edi+11], al            ; store checksum low byte
        mov     [edi+10], ah            ; store checksum high byte

        popa
        mov     eax, 0
        leave
        ret
