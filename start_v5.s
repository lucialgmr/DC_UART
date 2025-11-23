##############################################################################
# start.S - Programa de prueba UARTB0 para RV32E (LaRVa)
# - Sin C main, sin librerías, todo en ensamblador
# - Solo usa registros x0..x15 (zero, ra, sp, gp, tp, t0..t2, s0..s1, a0..a5)
##############################################################################

    .section .boot
    .globl reset_vec
reset_vec:
    j start

##############################################################################
# Código principal
##############################################################################
    .section .text
    .globl start
    .globl irq1_handler

start:
    ################################################################
    # 0) (Opcional) inicializar la pila
    ################################################################
    li   sp, 8192

    ################################################################
    # 1) Base de E/S: 0xE0000000  → a0
    ################################################################
    lui  a0, 0xE0000          # a0 = 0xE0000000

    ################################################################
    # 2) Configurar vector 4 del VIC con la dirección de irq1_handler
    #    Vector 4 está mapeado en 0xE00000E4
    ################################################################
    addi a1, a0, 0x0E4        # a1 = 0xE00000E4
    la   a2, irq1_handler     # a2 = &irq1_handler
    sw   a2, 0(a1)

    ################################################################
    # 3) Habilitar interrupción TX de UARTB0 (bit 3 de IRQEN)
    #    IRQEN está en 0xE00000E0
    ################################################################
    addi a1, a0, 0x0E0        # a1 = 0xE00000E0
    li   a2, 8                # 1 << 3
    sw   a2, 0(a1)

    ################################################################
    # 4) Configurar UARTB0 en modo normal (MODE=0, DIVIDER=7)
    #    UARTB_DATA: 0xE0000080
    #    UARTB_CTRL: 0xE0000084
    ################################################################
    addi a3, a0, 0x0080       # a3 = UARTB_DATA
    addi a4, a3, 4            # a4 = UARTB_CTRL
    li   a5, 7                # DIVIDER=7, MODE=0 (bit31=0)
    sw   a5, 0(a4)

    ################################################################
    # 5) Inicializar puntero al string "Hola mundo"
    ################################################################
    la   s0, msg              # s0 -> "Hola mundo\0"

    ################################################################
    # 6) Enviar primer carácter para arrancar la cadena de IRQs
    ################################################################
    lb   a1, 0(s0)            # a1 = *s0
    sw   a1, 0(a3)            # escribir en TX_data (UARTB_DATA)
    addi s0, s0, 1            # avanzar puntero

    ################################################################
    # 7) Esperar hasta recibir 0x00 por RX (polling en DV + RX_data)
    ################################################################
wait_zero:
    lw   a2, 0(a4)            # leer FLAGS de UARTB0 (DV en bit 0)
    andi a2, a2, 1
    beqz a2, wait_zero        # si DV=0, seguir esperando

    lw   a3, 0(a3)            # leer RX_data
    bnez a3, wait_zero        # mientras no sea 0x00, repetir

    ################################################################
    # 8) Pasar a modo ráfaga (MODE=1, DIVIDER=7)
    ################################################################
    li   a1, 7
    lui  a2, 0x80000          # bit 31 = 1
    or   a1, a1, a2           # MODE=1, DIVIDER=7
    sw   a1, 0(a4)

    ################################################################
    # 9) Enviar ráfaga "ABCD"
    ################################################################
    li   a2, 0x41424344       # 'A','B','C','D'
    sw   a2, 0(a3)

    ################################################################
    # 10) Enviar ráfaga "FGHI"
    ################################################################
    li   a2, 0x46474849       # 'F','G','H','I'
    sw   a2, 0(a3)

end_main:
    j end_main                # bucle infinito final


##############################################################################
# RUTINA DE SERVICIO DE INTERRUPCIÓN (ISR) PARA UARTB0 TX (thre_b0)
##############################################################################
# Cada vez que thre_b0 está a 1 y la IRQ está habilitada:
#   - Se envía el carácter apuntado por s0.
#   - Se incrementa s0.
#   - Si el carácter es 0x00, se deshabilita la interrupción y se termina.
##############################################################################

irq1_handler:
    # Base UARTB0 DATA = 0xE0000080 → a0
    lui  a0, 0xE0000
    addi a0, a0, 0x0080

    # Cargar siguiente carácter del string
    lb   a1, 0(s0)
    sw   a1, 0(a0)            # enviarlo

    beqz a1, irq_disable      # si es 0x00, deshabilitar IRQ

    addi s0, s0, 1            # avanzar puntero
    mret                      # volver de la interrupción

irq_disable:
    # IRQEN = 0 → deshabilitar todas las IRQ externas
    lui  a0, 0xE0000
    addi a0, a0, 0x0E0        # 0xE00000E0
    sw   zero, 0(a0)
    mret


##############################################################################
# Rutina de delay (por si se quisiera usar en pruebas)
##############################################################################
    .globl delay_loop
delay_loop:
    addi a0, a0, -1
    bnez a0, delay_loop
    ret


##############################################################################
# Datos de solo lectura
##############################################################################
    .section .rodata
msg:
    .asciz "Hola mundo"

