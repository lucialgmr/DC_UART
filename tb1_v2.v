//-------------------------------------------------------------------\
//-- Test Bench ADAPTADO para UARTB_CORE (Modo Normal, Modo Ráfaga y Loopback)
//-- Corregido: Uso de 'localparam' dentro de 'initial' para evitar errores
//-- de sintaxis con 'parameter' en algunos simuladores.
//-------------------------------------------------------------------\

`timescale 1ns/10ps
`include "uart_burst (1).v" // Se asume este nombre de archivo para el CORE

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
// Nota: La instancia usa las señales d[31:0] y el bit 31 se usa para el modo.
UARTB_CORE myUART(
  .txd(txd),
  // Puedes añadir aquí otras salidas como .tend(tend), .thre(thre), etc., si quieres visualizarlas
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
    
    // Constantes de simulación definidas localmente
    // Basado en: T_clk=20ns, Divisor=7+1=8 (BRG=7) -> T_baud = T_clk * 8 = 160 ns.
    // Usamos el valor real de tu UART: baud rate = clk / (divider+1)
    // El periodo de bit es (divider+1) * 2 * 10 ns. Con divider=7, es 8 * 20 ns = 160 ns.
    localparam T_DIVIDER = 7; // Valor del divisor que se usará.
    localparam T_BIT = (T_DIVIDER + 1) * 20;  // 8 * 20 ns = 160 ns
    localparam T_CHAR = T_BIT * 10;           // 10 bits por caracter (Start + 8 Datos + Stop)
    
    $display("--- Testbench UARTB Iniciado ---");
    $display("T_clk = 20 ns. Divisor (BRG) = %0d. T_bit = %0d ns.", T_DIVIDER, T_BIT);

    // 1. CONFIGURACIÓN INICIAL: DIVIDER=7 y MODE=0 (Normal)
    // Mode=0 (d[31]=0), Divisor=7 (d[8:0]=7)
    #50; // Pequeño retardo de inicio
    wrbaud = 1; 
    d = {32'h00000000 | T_DIVIDER}; // Forzado a 32'h00000007
    #20 wrbaud = 0;
    $display("@%0t: Configurado Modo Normal (MODE=0), Divisor=%0d.", $time, T_DIVIDER);
    #50;

    // 2. FASE MODO NORMAL (TX de 2 bytes: 'A', 'B')
    
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


    // 3. CONMUTACIÓN A MODO RÁFAGA (MODE=1)
    // Conmutamos a MODE=1 (bit 31), manteniendo DIVIDER=7
    wrbaud = 1; 
    // Bit 31 a 1, y el divisor a T_DIVIDER (7)
    d = 32'h80000000 | T_DIVIDER; // Forzado a 32'h80000007
    #10 wrbaud = 0;
    $display("@%0t: Conmutado a Modo Ráfaga (MODE=1).", $time);
    
    // Esperar a que 'B' termine de transmitirse
    #(T_CHAR / 2); 


    // 4. FASE MODO RÁFAGA (TX de 32 bits)
    // Enviar "ABCD" (0x44434241 - Little Endian, LSB primero)
    
    wrtx = 1; 
    d = 32'h44434241; // Escribir D C B A en el bus
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga 1 (0x44434241: DCBA).", $time);
    
    // Esperar la transmisión completa de la RÁFAGA (4 bytes * 10 ciclos de bit)
    #(T_CHAR * 4); 


    // 5. FASE MODO NORMAL FINAL (TX de 1 byte)
    // Regresar a Modo Normal (MODE=0) y enviar 'Z' (0x5A)
    wrbaud = 1; 
    d = 32'h00000000 | T_DIVIDER; // Forzado a 32'h00000007 (MODE=0, Divisor=7)
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
