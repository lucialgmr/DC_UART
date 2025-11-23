##############################################################################
# RESET & PROGRAMA DE TEST PARA UARTB0
##############################################################################

    .section .text
    .globl _start
    .globl irq1_handler

#----------------------------------------------------------------------
# Punto de entrada tras reset
#----------------------------------------------------------------------
_start:
    # Inicializar la pila (8KB de RAM basta para el test)
    li  sp, 8192

    # Llamar a main (programa de prueba)
    call main

# Si main terminara, nos quedamos en un bucle infinito
hang:
    j hang

##############################################################################
# PROGRAMA PRINCIPAL
##############################################################################
# Objetivos:
# 1) Configurar el VIC para que la interrupción de TX de UARTB0 (thre_b0)
#    use el vector 4.
# 2) Configurar UARTB0 en modo normal (MODE=0) con divisor 7.
# 3) Enviar "Hola mundo" carácter a carácter desde la ISR.
# 4) Esperar a recibir 0x00 por RX.
# 5) Pasar a modo ráfaga (MODE=1) y enviar "ABCD" y "FGHI".
##############################################################################

main:
    ##################################################################
    # a) Configurar vector de interrupción 4 (UARTB0 TX)
    ##################################################################
    # t0 = 0xE0000000
    lui t0, 0xE0000

    # Dirección del vector 4: 0xE00000E4
    addi t1, t0, 0x0E4      # t1 = 0xE00000E4

    # Cargar la dirección de irq1_handler
    la   t2, irq1_handler

    # Escribirla en el vector 4
    sw   t2, 0(t1)

    ##################################################################
    # b) Habilitar interrupción TX de UARTB0 (bit 3 de IRQEN)
    ##################################################################
    addi t3, t0, 0x0E0      # t3 = 0xE00000E0 (IRQEN)
    li   t4, 8              # 1 << 3
    sw   t4, 0(t3)

    ##################################################################
    # c) Configurar UARTB0 en modo normal, DIVIDER = 7
    ##################################################################
    addi t5, t0, 0x080      # t5 = 0xE0000080 (UARTB base)
    addi t6, t5, 4          # t6 = 0xE0000084 (DIVIDER/MODE)
    li   t7, 7              # MODE=0 (bit 31=0), DIVIDER=7
    sw   t7, 0(t6)

    ##################################################################
    # d) Inicializar puntero al string "Hola mundo"
    ##################################################################
    la   s0, msg            # s0 -> primer carácter

    ##################################################################
    # e) Forzar primera transmisión para arrancar la cadena de IRQs
    ##################################################################
wait_thre0:
    lw   a0, 0(t6)          # leer FLAGS/MODE/DIVIDER
    andi a1, a0, 0b00010    # THRE = bit 1
    beqz a1, wait_thre0

    lb   a2, 0(s0)          # primer carácter
    sw   a2, 0(t5)          # escribir en TX_data
    addi s0, s0, 1          # avanzar puntero

    ##################################################################
    # f) Bucle de espera: hasta que RX reciba 0x00
    ##################################################################
wait_zero:
    lw   a3, 0(t6)          # FLAGS
    andi a4, a3, 0b00001    # DV = bit 0
    beqz a4, wait_zero      # si no hay dato, seguir esperando

    lw   a5, 0(t5)          # leer RX_data (limpia DV)
    bnez a5, wait_zero      # mientras != 0x00, seguir

    ##################################################################
    # g) Pasar a modo ráfaga, mismo divisor
    ##################################################################
    li   a6, 7
    lui  a7, 0x80000        # bit 31 = 1
    or   a6, a6, a7         # MODE=1, DIVIDER=7
    sw   a6, 0(t6)

    ##################################################################
    # h) Enviar ráfaga "ABCD"
    ##################################################################
    li   t1, 0x41424344
    sw   t1, 0(t5)

    ##################################################################
    # i) Enviar ráfaga "FGHI"
    ##################################################################
    li   t1, 0x46474849
    sw   t1, 0(t5)

end_main:
    j end_main              # bucle infinito final

##############################################################################
# RUTINA DE SERVICIO DE INTERRUPCIÓN (ISR) PARA UARTB0 TX (thre_b0)
##############################################################################
# Cada vez que thre_b0 se activa:
#   - Se envía el carácter apuntado por s0.
#   - Se incrementa s0.
#   - Si el carácter es 0x00, se deshabilita la IRQ de TX y se sale.
##############################################################################

irq1_handler:
    # Base UARTB0 = 0xE0000080
    lui  t0, 0xE0000
    addi t0, t0, 0x080

    # Cargar siguiente carácter
    lb   t1, 0(s0)
    sw   t1, 0(t0)          # enviarlo

    beqz t1, isr_disable    # si es 0x00, fin de cadena

    addi s0, s0, 1          # avanzar puntero
    mret                    # volver de la interrupción

isr_disable:
    # Deshabilitar la interrupción TX (bit 3) poniendo IRQEN=0
    lui  t2, 0xE0000
    addi t2, t2, 0x0E0
    sw   zero, 0(t2)
    mret

##############################################################################
# Subrutina de delay (por si la necesitas en pruebas)
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
