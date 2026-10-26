; Loader ABI: DI, private loader stack, WIDTH 80,25 configured before bootstrap.
; No guessed ROM entry points. Write only character cells, preserve attributes.
org 0xd000
    ld hl,message
    ld de,0xf300
    ld bc,message_end-message
    ldir
    ret
message:
    db "HELLO FROM ZIG_80"
message_end:
