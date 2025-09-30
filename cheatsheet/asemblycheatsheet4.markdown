# x86 NASM Part 5: Variables, Constants, Arrays, and If-Else-If Cheat Sheet (Linux, Intel Syntax)

## Introduction
This is Part 5 of the x86 NASM assembly cheat sheet series for Linux (Debian 13), covering **variables** (creation, use), **constants**, **arrays/lists**, and **if-else-if logic** in 32-bit x86 with Intel syntax. Builds on Parts 1 (syntax), 2 (I/O/OS), 3 (functions/random), and 4 (loops, conditionals, strings). All terms are explained with examples for clarity.

## General Notes
- **Architecture**: x86 (32-bit), NASM Intel syntax, Linux system calls via `int 0x80`.
- **Registers**: Use `EAX`, `EBX`, `ECX`, `EDX` for operations; `ESI`/`EDI` for array indexing.
- **Variables**: Defined in `.data` (initialized) or `.bss` (uninitialized); accessed via `[label]` or `[reg+offset]`.
- **Constants**: Defined with `equ`, used as immediate values.
- **Arrays**: Stored as contiguous memory; indexed with offsets or registers.
- **If-Else-If**: Uses `CMP` and conditional jumps (`JE`, `JG`, etc.) for chained logic.
- **Assemble & Run**: `nasm -f elf32 file.asm -o file.o`; `ld -m elf_i386 file.o -o file`; `./file`.

## Defining and Using Variables
| Term | Description | Example |
|------|-------------|---------|
| `db` | Define byte(s) in `.data` (initialized). | `var1 db 42` |
| `dw` | Define word(s) (2 bytes) in `.data`. | `var2 dw 1234` |
| `dd` | Define doubleword(s) (4 bytes) in `.data`. | `var3 dd 56789` |
| `resb n` | Reserve n bytes in `.bss` (uninitialized). | `buf resb 64` |
| `resw n` | Reserve n words in `.bss`. | `buf resw 32` |
| `resd n` | Reserve n doublewords in `.bss`. | `buf resd 16` |
| `MOV dest, [var]` | Read variable into register. | `mov eax, [var1]` |
| `MOV [var], src` | Write to variable (src: reg, imm). | `mov [var1], 10` |
| Size specifiers | Use `byte`, `word`, `dword` for memory ops. | `mov byte [var1], al` |

**Notes**:
- Variables in `.data` are initialized; in `.bss`, they’re zeroed by the OS.
- Always specify size (`byte`, `word`, `dword`) for memory writes to avoid ambiguity.
- Restriction: No memory-to-memory moves (e.g., `mov [var1], [var2]` invalid).

## Defining Constants
| Term | Description | Example |
|------|-------------|---------|
| `equ` | Define constant (no memory allocation). | `MAX equ 100` |
| `$` | Current address in section (for lengths). | `len equ $ - str` |
| Use in instructions | Use constant as immediate value. | `mov eax, MAX` |

**Notes**:
- `equ` defines symbolic constants, replaced at assembly time.
- Use for sizes, syscall numbers, or fixed values.

## Arrays/Lists
| Term | Description | Example |
|------|-------------|---------|
| Define array | Use `db`, `dw`, `dd` for contiguous data. | `arr db 1, 2, 3, 4` |
| Reserve array | Use `resb`, `resw`, `resd` for uninitialized. | `arr resb 10` |
| Index array | Use `[base + offset]` or `[reg + offset]`. | `mov al, [arr + 2]` |
| Iterate array | Use `ESI`/`EDI` or loop with offset. | `mov esi, arr` <br> `mov al, [esi]` <br> `inc esi` |

**Notes**:
- Arrays are just memory blocks; no bounds checking.
- Index with `ESI` or calculate offset (e.g., `arr + 4` for second `dd` element).
- Use `REP MOVSB` (from Part 4) for array copying.

## If-Else-If Logic
| Term | Description | Example |
|------|-------------|---------|
| `CMP b, a` | Compare `b` - `a`, set flags (`ZF`, `SF`, `CF`, `OF`). | `cmp eax, 10` |
| `JE label` | Jump if equal (`ZF=1`). | `je equal` |
| `JNE label` | Jump if not equal (`ZF=0`). | `jne not_equal` |
| `JG label` | Jump if greater (signed, `ZF=0`, `SF=OF`). | `jg greater` |
| `JL label` | Jump if less (signed, `SF≠OF`). | `jl less` |
| Chained logic | Use jumps to chain conditions. | `cmp eax, 10` <br> `je case1` <br> `cmp eax, 20` <br> `je case2` <br> `jmp else` |

**Notes**:
- If-else-if requires multiple `CMP` and jumps to handle each condition.
- Use labels to structure logic flow; end with `JMP` to skip other cases.

## Example: Variable Usage
```nasm
section .data
    var1 db 42              ; Byte variable
    var2 dd 1000            ; Doubleword variable

section .bss
    buf resb 16             ; Uninitialized buffer

section .text
    global _start

_start:
    mov al, [var1]          ; Read byte
    add al, 10
    mov [var1], al          ; Write back
    mov eax, [var2]         ; Read doubleword
    mov [buf], eax          ; Store to buffer
    mov eax, 1
    mov ebx, 0
    int 0x80
```

## Example: Array Iteration
```nasm
section .data
    arr db 1, 2, 3, 4, 5    ; Byte array
    arr_len equ $ - arr

section .text
    global _start

_start:
    mov esi, arr            ; Array base
    mov ecx, arr_len        ; Loop counter
loop_start:
    mov al, [esi]           ; Read element
    ; Process al (e.g., print)
    inc esi                 ; Next element
    loop loop_start
    mov eax, 1
    mov ebx, 0
    int 0x80
```

## Example: If-Else-If Logic
```nasm
section .data
    num dd 15
    msg_eq db 'Equal 10', 10, 0
    msg_gt db 'Greater than 10', 10, 0
    msg_else db 'Else case', 10, 0

section .text
    global _start

_start:
    mov eax, [num]
    cmp eax, 10             ; If num == 10
    je case_eq
    cmp eax, 10             ; Else if num > 10
    jg case_gt
    jmp case_else           ; Else

case_eq:
    mov eax, 4
    mov ebx, 1
    mov ecx, msg_eq
    mov edx, 9
    int 0x80
    jmp exit

case_gt:
    mov eax, 4
    mov ebx, 1
    mov ecx, msg_gt
    mov edx, 14
    int 0x80
    jmp exit

case_else:
    mov eax, 4
    mov ebx, 1
    mov ecx, msg_else
    mov edx, 10
    int 0x80

exit:
    mov eax, 1
    mov ebx, 0
    int 0x80
```

## Tips
- **Variables**: Use `.data` for initialized, `.bss` for dynamic data; always specify size for memory ops.
- **Constants**: Use `equ` for readability (e.g., `SYS_WRITE equ 4`).
- **Arrays**: Calculate offsets carefully (e.g., `dd` elements are 4 bytes apart).
- **If-Else-If**: Chain `CMP` and jumps; ensure `JMP` to skip unneeded cases.
- **Debug**: Use `gdb` (`gdb ./file`, `break _start`, `run`, `nexti`).
- **Resources**: `man 2 syscall`, nasm.us, godbolt.org.

**Assemble & Run** (Debian 13):
```bash
nasm -f elf32 file.asm -o file.o
ld -m elf_i386 file.o -o file
./file
```