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
### Main program
######################################

start:
# DESDE AQUI changed_RP

# CONFIGURO VIC PARA INTERRUPCIÓN POR GPO
li a0, 0xE00000E0 # a0 dirección base del VIC
li a1, 0x00000004
sw a1, 0 (a0)     # habilito la interrupción desde CPO (cuando GPO=0x00FF_00FF)

la a1, irs_GPO
sw a1, 0x1C(a0)   # escribo vector en dir 0xE000_00FC

# escribo en el GPO - primero en tamaño word (32 bits)
li a0, 0xE0000040 # dirección base del GPO
li a1, 0xA555AAAA
sw a1, 0(a0)     # store tamaño word

end:
 j end			# end

irs_GPO:


	mret

#HASTA AQUI changed_RP
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
