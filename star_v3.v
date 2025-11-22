# 1 "Firmware/start.S"
# 1 "<built-in>"
# 1 "<command-line>"
# 31 "<command-line>"
# 1 "/usr/include/stdc-predef.h" 1 3 4
# 32 "<command-line>" 2
# 1 "Firmware/start.S"

##############################################################################
# RESET & IRQ
##############################################################################

 .global main, irq1_handler, irq2_handler, irq3_handler

 .section .boot
reset_vec:
 j start
.section .text

######################################
### Código de arranque
######################################

start:
 li sp,8192                    # inicializa la pila                  #changed

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
# call main de nuestro programa de test
 call main                                                           #changed
loop:
 j loop

######################################
### Programa principal (test UARTB)
######################################

# Tareas:
# 1) Configurar VIC: vector para thre_b0 en 0xE00000E4
# 2) Configurar UARTB0 en modo normal (MODE=0) con DIVIDER=8
# 3) Crear string "Hola mundo" (.asciz) y poner puntero en s0
# 4) Habilitar interrupción thre_b0 (bit 3 de IRQEN)
# 5) Esperar en bucle hasta recibir 0x00 por la UARTB0 (loopback TXD->RXD)
# 6) ISR (irq1_handler): en cada thre_b0 envía un carácter y avanza s0
#    Cuando envía 0x00, deshabilita la interrupción
# 7) Reconfigurar UARTB0 en modo ráfaga (MODE=1) y enviar "ABCD" y "FGHI"

main:                                                                #changed
    ############################################################
    # 1) Base de la nueva UARTB0: 0xE0000080
    ############################################################
    lui a0, 0xE0000              # a0 = 0xE0000000               #changed
    addi a0, a0, 0x080           # a0 = 0xE0000080 (uartb0)      #changed

    ############################################################
    # 2) Configurar vector de interrupción para thre_b0
    #    Vector 4 mapeado en 0xE00000E4 (según system.v)
    ############################################################
    lui t0, 0xE0000              # t0 = 0xE0000000               #changed
    addi t0, t0, 0x0E4           # t0 = 0xE00000E4 (vector 4)    #changed
    la   t1, irq1_handler        # dirección de la ISR           #changed
    sw   t1, 0(t0)               # VIC.vector4 <- irq1_handler   #changed

    ############################################################
    # 3) Configurar UARTB0 en modo normal (MODE=0), DIVIDER=8
    #    Registro en 0xE0000084: [31]=MODE, [7:0]=DIVIDER
    ############################################################
    li   t1, 8                   # DIVIDER = 8                   #changed
    sw   t1, 4(a0)               # MODE=0, DIVIDER=8             #changed

    ############################################################
    # 4) Crear string y fijar puntero en s0
    ############################################################
    la   s0, msg                 # s0 -> "Hola mundo\0"          #changed

    ############################################################
    # 5) Habilitar línea de interrupción thre_b0 (bit 3 de IRQEN)
    #    IRQEN está en 0xE00000E0
    ############################################################
    lui  t0, 0xE0000             # t0 = 0xE0000000               #changed
    addi t0, t0, 0x0E0           # t0 = 0xE00000E0 (IRQEN)       #changed
    li   t1, (1 << 3)            # bit 3 = UARTB0 TX (thre_b0)   #changed
    sw   t1, 0(t0)               # habilitar solo thre_b0        #changed

    ############################################################
    # 6) Bucle de espera hasta recibir 0x00 por RX de uartb0
    #    Se supone loopback TXD_B0 -> RXD_B0 en tb.v
    ############################################################
wait_char:                                                           #changed
    lw   t2, 4(a0)               # leer FLAGS uartb0              #changed
    andi t2, t2, 1               # DV (bit 0) ?                   #changed
    beqz t2, wait_char           # si no hay dato, seguir         #changed

    lb   t3, 0(a0)               # leer RX_data (byte recibido)   #changed
    bnez t3, wait_char           # si != 0x00, seguir esperando   #changed

    # Si hemos recibido 0x00 -> fin de string                    #changed

    ############################################################
    # 7) Reconfigurar UARTB0 en modo ráfaga (MODE=1)
    #    con el mismo DIVIDER=8
    ############################################################
    li   t1, 8                   # DIVIDER = 8                    #changed
    lui  t2, 0x80000             # t2 = 0x80000000 (bit 31=1)     #changed
    or   t1, t1, t2              # MODE=1 en bit 31               #changed
    sw   t1, 4(a0)               # escribir MODE/DIVIDER          #changed

    ############################################################
    # 8) Enviar dos ráfagas de 32 bits: "ABCD" y "FGHI"
    #    Se escriben como palabras en TX_data (0xE0000080)
    ############################################################
    li   t1, 0x41424344          # 'A','B','C','D'                #changed
    sw   t1, 0(a0)               # ráfaga 1                       #changed
    li   t1, 0x46474849          # 'F','G','H','I'                #changed
    sw   t1, 0(a0)               # ráfaga 2                       #changed

end_main:                                                            #changed
    j end_main                   # bucle infinito final           #changed


######################################
### Rutina de servicio de interrupción
### irq1_handler: ISR de thre_b0 (UARTB0 TX ready)
######################################

irq1_handler:                                                        #changed
    # Base de UARTB0 = 0xE0000080                                  #changed
    lui  t0, 0xE0000             # t0 = 0xE0000000                 #changed
    addi t0, t0, 0x080           # t0 = 0xE0000080                 #changed

    # Leer siguiente carácter del string apuntado por s0           #changed
    lb   t1, 0(s0)               # t1 = *s0                        #changed
    sb   t1, 0(t0)               # enviar carácter por UARTB0      #changed

    beqz t1, isr_disable_irq     # si es 0x00, deshabilitar IRQ    #changed

    addi s0, s0, 1               # avanzar puntero al siguiente    #changed
    mret                         # volver de la interrupción       #changed

isr_disable_irq:                                                     #changed
    # Deshabilitar todas las interrupciones externas (IRQEN=0)     #changed
    lui  t0, 0xE0000             # t0 = 0xE0000000                 #changed
    addi t0, t0, 0x0E0           # t0 = 0xE00000E0 (IRQEN)         #changed
    sw   zero, 0(t0)             # IRQEN <- 0                      #changed
    mret                         # volver tras enviar 0x00         #changed


######################################
### delay_loop (se mantiene igual)
######################################

 .globl delay_loop
delay_loop:
 addi a0,a0,-1
 bnez a0, delay_loop
 ret

######################################
### String usado por el programa
######################################

# Colocamos el string al final del fichero para evitar problemas
# de alineamiento en la memoria de programa.
msg:                                                                 #changed
    .asciz "Hola mundo"                                              #changed
