//-------------------------------------------------------------------\
//-- Test Bench ADAPTADO para UARTB_CORE (Modo Normal, Modo Ráfaga y Loopback)
//-- Adaptado para usar d[31] como bit de modo.
//-------------------------------------------------------------------\

`timescale 1ns/10ps
`include "uart_burst.v" // Se asume este nombre de archivo para el CORE

module tb();

//-- Registos con señales de entrada
reg clk=0;
reg rxd=1;        // Entrada RX (inicializada a IDLE=1)
reg wrtx=0;       // Pulso de escritura TX
reg wrbaud=0;     // Pulso de escritura BRG/Mode
reg[31:0] d;      // Bus de 32 bits (Datos TX o Configuración)
reg rd = 0;       // Pulso de lectura RX (borra DV)

// Señal de salida TX del módulo
wire txd;

// Se asume que UARTB_CORE es la instancia de tu módulo
UARTB_CORE myUART(
  .txd(txd),
  //... otras salidas de flag (tend, thre, dv, etc.) - Si existen, se visualizan.
  .d(d),          // Datos TX/BRG
  .wrtx(wrtx),    // Escritura en TBR
  .wrbaud(wrbaud),// Escritura en BRG/Mode
  .rxd(rxd),      // Entrada RX
  .rd(rd),        // Lectura RX
  .clk(clk)
);

//--- LOOPBACK: Cortocircuita txd con rxd ---
// txd debe ir a rxd. Usamos un pequeño retardo (#1) para simular la propagación.
always @(txd) begin
    #1 rxd = txd;
end
//-------------------------------------------

// Generación de Reloj: Periodo de 20 ns (50 MHz)
always #10 clk=~clk;	

//-- Proceso de Test
initial begin
    //-- Fichero donde almacenar los resultados
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    
    // Parámetros de simulación
    parameter T_BIT = 1660;  // 8 * 20 ns * 10 (aprox. 160ns, usando un divisor de 7+1=8)
    parameter T_CHAR = T_BIT * 10; // 10 bits por caracter (Start + 8 Datos + Stop)
    
    $display("--- Testbench UARTB Iniciado ---");

    // 1. CONFIGURACIÓN INICIAL: DIVIDER=7 y MODE=0 (Normal)
    // Mode=0 (d[31]=0), Divisor=7 (d[8:0]=7)
    #50; // Pequeño retardo de inicio
    wrbaud = 1; 
    d = 32'h00000007; // 0x00000007
    #20 wrbaud = 0;
    $display("@%0t: Configurado Modo Normal (MODE=0), Divisor=7.", $time);
    #50;

    // 2. FASE MODO NORMAL (TX de 1 byte)
    // Se enviarán 'A' (0x41), 'B' (0x42)
    
    // Enviar 'A' (0x41). Se usa d[7:0] como byte menos significativo.
    wrtx = 1; d = 32'h00000041; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'A' (Modo Normal).", $time);
    
    // Esperar la transmisión completa de 'A' (aprox. 10 ciclos de bit)
    #(T_CHAR); 

    // Enviar 'B' (0x42)
    wrtx = 1; d = 32'h00000042; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'B' (Modo Normal).", $time);
    
    // Esperar un tiempo intermedio antes de conmutar
    #(T_CHAR / 2); 


    // 3. CONMUTACIÓN DURANTE LA TRANSMISIÓN: Modo Ráfaga (MODE=1)
    // Conmutamos a MODE=1, pero mantenemos DIVIDER=7
    wrbaud = 1; 
    d = 32'h80000007; // 0x80000007 (d[31]=1 para Ráfaga, d[8:0]=7)
    #10 wrbaud = 0;
    $display("@%0t: Conmutado a Modo Ráfaga (MODE=1).", $time);
    
    // Esperar a que 'B' termine de transmitirse
    #(T_CHAR / 2); 


    // 4. FASE MODO RÁFAGA (TX de 32 bits)
    // Enviar "ABCD" (0x44434241 - Little Endian, LSB primero)
    // La CPU escribe la palabra completa en una única operación.
    
    wrtx = 1; 
    d = 32'h44434241; // D C B A
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga 1 (ABCD, 32-bit).", $time);
    
    // Esperar la transmisión completa de la RÁFAGA (4 * 10 ciclos de bit)
    #(T_CHAR * 4); 

    // Enviar "FGHI" (0x49484746)
    wrtx = 1; 
    d = 32'h49484746; // I H G F
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga 2 (IHGF, 32-bit).", $time);

    // Esperar la transmisión completa de la RÁFAGA 2
    #(T_CHAR * 4); 


    // 5. FASE MODO NORMAL FINAL (TX de 1 byte)
    // Regresar a Modo Normal (MODE=0) y enviar 'Z' (0x5A)
    wrbaud = 1; 
    d = 32'h00000007; // 0x00000007 (MODE=0, Divisor=7)
    #10 wrbaud = 0;
    $display("@%0t: Conmutado de nuevo a Modo Normal (MODE=0).", $time);
    
    #50;
    // Enviar 'Z' (0x5A)
    wrtx = 1; d = 32'h0000005A; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'Z' (Modo Normal Final).", $time);

    // Limpiar flag DV (Simular lectura por la CPU, si es necesario)
    #50 rd = 1;
    #10 rd = 0;

    // Finalización de la simulación
	# 3000 $finish;
end

endmodule
