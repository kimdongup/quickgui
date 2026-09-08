bits 16
org 0x7c00
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7c00
    sti
    cld
    mov byte [0x500], 0
    mov ax, 3
    int 0x10
    mov si, prompt
    call print
read_key:
    xor ax, ax
    int 0x16
    cmp al, 'k'
    jne read_key
    mov byte [0x500], 1
    mov si, success
    call print
halt:
    hlt
    jmp halt
print:
    lodsb
    test al, al
    jz done
    mov ah, 0x0e
    mov bx, 7
    int 0x10
    jmp print
done:
    ret
prompt: db 'Quickgui SPICE test - press K', 13, 10, 0
success: db 'KEYBOARD PASS', 13, 10, 0
times 510 - ($-$$) db 0
dw 0xaa55
