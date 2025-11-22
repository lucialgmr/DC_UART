# 1 "Firmware/start.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 31 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 32 "<command-line>" 2
# 1 "Firmware/start.S"

##############################################################################
# Datos (String)
##############################################################################
 .section .rodata
string_data:
 .asciz "Hola mundo" # Termina con 0x00

##############################################################################
# RESET & IRQ
##############################################################################

 .global main, irq1_handler, irq2_handler, irq3_handler

 .section .boot
reset_vec:
 j start
.section .text

######################################
### Main program
######################################

start:
# DESDE AQUI modified1511 (NUEVA IMPLEMENTACIÓN)

# ----------------------------------------------------
# 1. CONFIGURACIÓN INICIAL DEL VIC (Vectores)
# ----------------------------------------------------
# Carga el vector de interrupción para THRE (IRQ Vector 2)
li a0, 0xE00000F8      # Dirección del IRQ Vector 2 (TX)
la a1, isr_thre        # Dirección de la rutina ISR
sw a1, 0(a0)           # Escribe el vector

# ----------------------------------------------------
# 2. CONFIGURACIÓN DE UARTB - MODO NORMAL (MODE=0)
# ----------------------------------------------------
# Frecuencia 8 veces menor que la CPU (DIVIDER = 7). MODE=0.
li a1, 0x00000007      # D[31]=0 (Normal) | DIVIDER=7
li a0, 0xE0000084      # Dirección de Configuración/Baud
sw a1, 0(a0)           # Configura la velocidad y el modo normal

# ----------------------------------------------------
# 3. SETUP DEL STRING Y PUNTERO
# ----------------------------------------------------
la s0, string_data     # s0 = puntero al string "Hola mundo"

# ----------------------------------------------------
# 4. HABILITAR INTERRUPCIÓN THRE
# ----------------------------------------------------
# Habilita el bit 1 (UART TX interrupt) del IRQ Enable [cite: 11]
li a0, 0xE00000E0      # Dirección del IRQ Enable
li a1, 0x00000002      # Bit 1 (TX) = 1
sw a1, 0(a0)           # Habilita la interrupción THRE

# ----------------------------------------------------
# 5. INICIO DE TRANSMISIÓN Y BUCLE DE ESPERA
# ----------------------------------------------------
# La primera transmisión debe ser manual para cebar el ISR.
# Carga el primer carácter y lo envía.
lb a1, 0(s0)           # Carga el primer byte ('H')
addi s0, s0, 1         # Incrementa el puntero
li a0, 0xE0000080      # Dirección de Datos TX
sw a1, 0(a0)           # Envía el primer carácter, esto llenará el THR.
                       # Cuando el Shift Register tome el byte, THRE se activará, generando la primera interrupción.

# Bucle de espera. Sólo saldrá con mret del ISR cuando finalice el string.
wait_loop:
 j wait_loop           # El control volverá aquí tras cada interrupción.


# ----------------------------------------------------
# 6. MODO POST-TRANSMISIÓN (Se ejecuta después de salir del ISR)
# ----------------------------------------------------
# a) Deshabilitar interrupción THRE
li a0, 0xE00000E0      # Dirección del IRQ Enable
sw zero, 0(a0)         # Deshabilita todas las IRQs (TX bit 1)

# b) Configurar UARTB a MODO RÁFAGA (MODE=1) - MISMA VELOCIDAD (DIVIDER=7)
li a1, 0x80000007      # D[31]=1 (Ráfaga) | DIVIDER=7
li a0, 0xE0000084      # Dirección de Configuración/Baud
sw a1, 0(a0)           # Configura la UARTB a modo ráfaga

# c) Transmisión Ráfaga 1: "ABCD" (0x44434241)
li a1, 0x44434241      # Word 1: "ABCD" (LSB: A, MSB: D)
li a0, 0xE0000080      # Dirección de Datos TX
sw a1, 0(a0)           # Envía la primera ráfaga

# (Opcional) Esperar un poco para garantizar que la primera ráfaga inicia/termina
li a2, 10000
call delay_loop

# d) Transmisión Ráfaga 2: "FGHI" (0x49484746)
li a1, 0x49484746      # Word 2: "FGHI" (LSB: F, MSB: I)
sw a1, 0(a0)           # Envía la segunda ráfaga

# ----------------------------------------------------
# 7. BUCLE INFINITO FINAL
# ----------------------------------------------------
end:
 j end            # end

##############################################################################
# Interrupt Service Routine (ISR) para THRE
##############################################################################
isr_thre:
    # 1. Cargar el siguiente carácter
    lb a1, 0(s0)            # Carga el byte al que apunta s0

    # 2. Comprobar End of String (0x00)
    bnez a1, send_char      # Si no es 0x00, saltar a enviar
    
    # FIN DEL STRING: Deshabilitar interrupción y salir del bucle principal
    
    # 2.1. Deshabilitar Interrupción THRE (Bit 1)
    li a0, 0xE00000E0       # Dirección IRQ Enable
    li a2, 0x00000002       # Máscara para borrar bit 1 (la instrucción es WR, no AND/CLR)
    # Se asume que el registro de habilitación es de sólo escritura y que
    # se escribe sólo el bit que se quiere habilitar, si no, se necesita guardar
    # el estado anterior y usar el CSR. En este micro, es un registro simple:
    sw zero, 0(a0)          # Deshabilitar todas las IRQs (para simplificar)
    
    # 2.2. Salir del bucle wait_loop
    la ra, post_isr         # Cargar la dirección de retorno después del bucle
    mret                    # Regresa al programa principal (en 'post_isr')

send_char:
    # 3. Enviar el carácter
    li a0, 0xE0000080       # Dirección de Datos TX
    sw a1, 0(a0)            # Escribe el carácter (envía 1 byte)

    # 4. Incrementar puntero
    addi s0, s0, 1          # s0 apunta al siguiente byte

    mret                    # Regresa al bucle wait_loop

post_isr:
    # El código continua en el punto 6 (MODO POST-TRANSMISIÓN) del programa principal

#HASTA AQUI modified1511 (NUEVA IMPLEMENTACIÓN)

 li sp,8192

# copy data section
 la a0, _sdata
 la a1, _sdata_values
 la a2, _edata
 bge a0, a2, end_init_data
loop_init_data:
 lw a3,0(a1)
 sw a3,0(a0)
 addi a0,a0,4
 addi a1,a1,4
 blt a0, a2, loop_init_data
end_init_data:
# zero-init bss section
 la a0, _sbss
 la a1, _ebss
 bge a0, a1, end_init_bss
loop_init_bss:
 sw zero, 0(a0)
 addi a0, a0, 4
 blt a0, a1, loop_init_bss
end_init_bss:
# call main
 call main
loop:
 j loop

 .globl delay_loop
delay_loop:
 addi a0,a0,-1
 bnez a0, delay_loop
 ret
