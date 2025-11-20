//-------------------------------------------------------------------\
//-- Test Bench ADAPTADO para UARTB_CORE (Modo Normal, Modo Ráfaga y Loopback)
//-- Solución 3: Constantes de tiempo definidas como localparam
//--             *dentro* del bloque 'initial' para máxima compatibilidad.
//-------------------------------------------------------------------\

`timescale 1ns/10ps
`include "uart_burst.v" // Se asume este nombre de archivo para el CORE

module tb();

//-- Registros con señales de entrada
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
  .d(d),
  .wrtx(wrtx),
  .wrbaud(wrbaud),
  .rxd(rxd),
  .rd(rd),
  .clk(clk)
);

//--- LOOPBACK: Cortocircuita txd con rxd ---
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
    
    // Constantes de simulación definidas localmente y USADAS INMEDIATAMENTE
    // T_clk=20ns, Divisor=7+1=8 (BRG=7) -> T_bit = T_clk * 8 = 160 ns.
    localparam T_DIVIDER = 7;
    localparam T_BIT = (T_DIVIDER + 1) * 20;  // 160 ns
    localparam T_CHAR = T_BIT * 10;           // 1600 ns (10 bits: Start + 8 Datos + Stop)
    
    $display("--- Testbench UARTB Iniciado ---");
    $display("T_clk = 20 ns. Divisor (BRG) = %0d. T_bit = %0d ns.", T_DIVIDER, T_BIT);

    // 1. CONFIGURACIÓN INICIAL: DIVIDER=7 y MODE=0 (Normal)
    #50;
    wrbaud = 1; 
    d = {32'h00000000 | T_DIVIDER};
    #20 wrbaud = 0;
    $display("@%0t: Configurado Modo Normal (MODE=0), Divisor=%0d.", $time, T_DIVIDER);
    #50;

    // 2. FASE MODO NORMAL (TX de 2 bytes: 'A', 'B')
    
    // Enviar 'A' (0x41).
    wrtx = 1; d = 32'h00000041; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'A' (Modo Normal).", $time);
    
    // Esperar la transmisión completa de 'A' 
    #(T_CHAR); 

    // Enviar 'B' (0x42)
    wrtx = 1; d = 32'h00000042; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'B' (Modo Normal).", $time);
    
    // Esperar un tiempo intermedio antes de conmutar
    #(T_CHAR / 2); 


    // 3. CONMUTACIÓN A MODO RÁFAGA (MODE=1)
    // Conmutamos a MODE=1 (bit 31), manteniendo DIVIDER=7
    wrbaud = 1; 
    d = 32'h80000000 | T_DIVIDER; 
    #10 wrbaud = 0;
    $display("@%0t: Conmutado a Modo Ráfaga (MODE=1).", $time);
    
    // Esperar a que 'B' termine de transmitirse
    #(T_CHAR / 2); 


    // 4. FASE MODO RÁFAGA (TX de 32 bits)
    // Enviar "ABCD" (0x44434241 - Little Endian, LSB primero)
    wrtx = 1; 
    d = 32'h44434241; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga 1 (0x44434241: DCBA).", $time);
    
    // Esperar la transmisión completa de la RÁFAGA (4 bytes * 10 ciclos de bit)
    #(T_CHAR * 4); 


    // 5. FASE MODO NORMAL FINAL (TX de 1 byte)
    // Regresar a Modo Normal (MODE=0) y enviar 'Z' (0x5A)
    wrbaud = 1; 
    d = 32'h00000000 | T_DIVIDER; 
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
