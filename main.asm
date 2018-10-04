%include "server.asm"
%define stderr 1

section .data
    syntax              db    "Usage:", 10, "  http-asm <port> <path>", 10
    syntaxLength        equ   $ - syntax
    bindError           db    "http-asm: An error has occured when tried to create and bind TCP socket. ",\
                              "Perhaps a port is already in use?"
    bindErrorLength     equ   $ - bindError
    
section .text
    
; input: rdi - null terminated string
; output: rax - result, or 0 on fail
; mutates: rcx
_parse_integer:
    xor rax, rax
    xor rcx, rcx
    .loop:   
        mov cl, [rdi]
        test cl, cl
        jz .end
        
        cmp cl, '0'
        jb .error
        cmp cl, '9'
        ja .error
        
        mov rbx, 10
        mul rbx
        add rax, rcx
        sub rax, '0'
        inc rdi
    jmp .loop
    .error:
    mov rax, 0
    .end:
    ret


; input: rdi - argc
;        rsi - argv
; output: rax - port's integer representation or 0 on syntax error
;         path - pointer to path to the server root
;         pathLength - length of `path`
_parse_arguments:
    cmp rdi, 3
    jne .error

    mov rdi, [rsi + 16]
    mov [path], rdi
    xor rax, rax
    .strlen_loop:
        mov cl, [rdi + rax]
        test cl, cl
        jz .end_loop
        inc rax
     jmp .strlen_loop
    .end_loop:
    mov [pathLength], rax
            
    mov rdi, [rsi + 8]
    call _parse_integer
    test rax, rax
    jz .error    
    jmp .end
    .error:
    mov rax, 0
    .end:
    ret

section .data
    
    testPort db "8080", 0
    testPath db "/home/vlad/", 0
    argc     dq 0, testPort, testPath

section .text  


; input: rdi - client's descriptor
; output: none
_handle_client:
    push rbp
    mov rbp, rsp
    sub rsp, LINE_BUFFER_SIZE
    mov rcx, rdi
    mov r9, rcx        
    lea rsi, [rbp - LINE_BUFFER_SIZE]
    call _read_line
    test rax, rax
    jz .bad_request
    
    lea rdi, [rbp - LINE_BUFFER_SIZE]
    call _parse_request
    test rax, rax
    jz .unsupported_method

    push rax
    xor rcx, rcx
    .terminate_path_loop:
        mov cl, [rax]
        cmp cl, ' '
        je .terminate_path_loop_end
        cmp cl, 13
        je .terminate_path_loop_end
        cmp cl, '?'
        je .terminate_path_loop_end
        inc rax
    jmp .terminate_path_loop
    .terminate_path_loop_end:
    mov [rax], BYTE 0
    mov rdi, [rsp]
    push rdi
    call _url_decode
    pop rdi
    pop rax
            
    mov rsp, rax
    mov rcx, [pathLength]
    sub rsp, rcx
    mov rdi, [path]
    mov rsi, rsp
    .strcopy:
        mov al, [rdi]
        mov [rsi], al
        inc rsi
        inc rdi
    loop .strcopy
    
    mov rsi, r9 ; socket descr.
    mov rdi, rsp
    call _serve_file
    
    jmp .end
    
    .unsupported_method:
    mov rax, write_sc
    mov rdi, r9
    mov rsi, respError405
    mov rdx, respError405Length
    syscall
    jmp .end
        
    .bad_request:
    mov rax, write_sc
    mov rdi, r9
    mov rsi, respError400
    mov rdx, respError400Length
    syscall
    
    .end:
    mov rsp, rbp
    pop rbp
    ret



global main
main:
    mov rbp, rsp; for correct debugging
    
    mov rdi, 3
    mov rsi, argc
    
    call _parse_arguments
    test rax, rax
    jz .error_syntax
    
    mov rdi, rax
    call _init_server
    cmp rax, -1
    je .error_bind
    
    mov rdi, rax
    call _server_loop
    
    .error_syntax:
    mov rax, write_sc
    mov rdi, stderr
    mov rsi, syntax
    mov rdx, syntaxLength
    syscall
    jmp .end
    
    .error_bind:
    mov rax, write_sc
    mov rdi, stderr
    mov rsi, bindError
    mov rdx, bindErrorLength
    syscall
    
    .end:
    xor rax, rax
    ret