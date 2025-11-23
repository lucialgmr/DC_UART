    .section .text
    .globl _start

#--------------------------------------------------------
# Direcciones de la UARTB0
#--------------------------------------------------------
UARTB_BASE  = 0xE0000080
UARTB_DATA  = 0xE0000080
UARTB_CTRL  = 0xE0000084

# IRQ de TX de UARTB en vector 4 (0xE00000E4)
IRQ_VEC4    = 0xE00000E4
IRQ_EN      = 0xE00000E0

#--------------------------------------------------------
# RESET → start
#--------------------------------------------------------
_start:

    # Configurar vector de interrupción para UARTB0 TX
    la   t0, irq1_handler
    sw   t0, IRQ_VEC4(t1)      # escribir en 0xE00000E4  //changed

    # Habilitar interrupción thre_b0 (bit 3)
    li   t0, 0b01000
    sw   t0, IRQ_EN(t1)         //changed

    #---------------------------------------------------
    # Configurar UARTB en modo normal (MODE=0)
    # divisor = 7  → baudios = Fclk/(7+1)
    # escritura en 0xE0000084
    #---------------------------------------------------
    li   t0, 7
    sw   t0, UARTB_CTRL(t1)     //changed

    #---------------------------------------------------
    # Definir string "Hola mundo"
    #---------------------------------------------------
    la   s0, mensaje

    #---------------------------------------------------
    # Enviar primer carácter por polling para arrancar ISR
    #---------------------------------------------------
send_first:
    lw   t2, UARTB_CTRL(t1)
    andi t2, t2, 0b00010         # THRE bit
    beqz t2, send_first

    lb   t3, 0(s0)
    sw   t3, UARTB_DATA(t1)      #changed

    # avanzar puntero
    addi s0, s0, 1

#--------------------------------------------------------
# Bucle de espera: esperar a recibir un 0x00 por RX
#--------------------------------------------------------
wait_end:
    lw   t4, UARTB_CTRL(t1)
    andi t4, t4, 0b00001   # DV
    beqz t4, wait_end
    lw   t5, UARTB_DATA(t1)
    bnez t5, wait_end      # esperar 0

    j next_phase

#--------------------------------------------------------
# ISR – envío carácter a carácter
#--------------------------------------------------------
irq1_handler:
    # cargar byte
    lb   t6, 0(s0)
    beqz t6, end_normal

    sw   t6, UARTB_DATA(t1)
    addi s0, s0, 1
    mret

end_normal:
    # deshabilitar interrupción TX (bit 3)
    li t0, 0
    sw t0, IRQ_EN(t1)
    mret

#--------------------------------------------------------
# SEGUNDA FASE – MODO RÁFAGA
#--------------------------------------------------------
next_phase:

    # MODE=1  (bit 31)
    li t0, (1<<31) | 7
    sw t0, UARTB_CTRL(t1)

    # enviar "ABCD"
    li t0, 0x41424344
    sw t0, UARTB_DATA(t1)

    # enviar "FGHI"
    li t0, 0x46474849
    sw t0, UARTB_DATA(t1)

end:
    j end

#--------------------------------------------------------
# Datos
#--------------------------------------------------------
    .section .rodata
mensaje:
    .asciz "Hola mundo"
