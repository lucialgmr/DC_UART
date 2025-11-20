//-------------------------------------------------------------------\
//-- Test Bench ADAPTADO para UARTB_CORE (Modo Normal, Ráfaga y Loopback)
//-- SOLUCIÓN: Garantiza la conmutación del bit de MODO (d[31]) y usa
//--           valores numéricos fijos para máxima compatibilidad.
//-- CÁLCULOS: Clock=20ns, BRG=7 -> T_bit=160ns, T_char=1600ns (10 bits)
//-------------------------------------------------------------------\

`timescale 1ns/10ps
`include "uart_burst.v" 

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

// Valor constante para el divisor BRG (7 -> 8 ciclos de reloj por bit)
localparam T_DIVIDER = 7; 
localparam T_CHAR = 1600; // 10 * 160 ns = 1600 ns

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
    
    $display("--- Testbench UARTB Iniciado ---");
    $display("T_clk = 20 ns. Divisor (BRG) = %0d. T_char = %0d ns.", T_DIVIDER, T_CHAR);

    // 1. CONFIGURACIÓN INICIAL: DIVIDER=7 y MODE=0 (Normal)
    #50;
    wrbaud = 1; 
    // MODO NORMAL (d[31]=0) + Divisor (T_DIVIDER=7) = 32'h00000007
    d = {32'h00000000 | T_DIVIDER}; 
    #20 wrbaud = 0;
    $display("@%0t: Configurado: MODO NORMAL (d=%h).", $time, d);
    #50;

    // 2. FASE MODO NORMAL (TX de 2 bytes: 'A', 'B')
    
    // Enviar 'A' (0x41).
    wrtx = 1; d = 32'h00000041; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'A' (Modo Normal).", $time);
    
    // Esperar la transmisión completa de 'A' (1600 ns)
    #1600; 

    // Enviar 'B' (0x42)
    wrtx = 1; d = 32'h00000042; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'B' (Modo Normal).", $time);
    
    // Esperar un tiempo intermedio antes de conmutar (800 ns = 1/2 T_CHAR)
    #800; 


    // 3. CONMUTACIÓN A MODO RÁFAGA (MODE=1)
    wrbaud = 1; 
    // MODO RÁFAGA (d[31]=1) + Divisor (T_DIVIDER=7) = 32'h80000007
    d = 32'h80000000 | T_DIVIDER; 
    #20 wrbaud = 0;
    $display("@%0t: Configurado: MODO RÁFAGA (d=%h).", $time, d);
    
    // Esperar a que 'B' termine de transmitirse (800 ns restantes)
    #800; 


    // 4. FASE MODO RÁFAGA (TX de 32 bits)
    // Enviar "ABCD" (0x44434241)
    wrtx = 1; 
    d = 32'h44434241; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga (0x44434241: DCBA).", $time);
    
    // Esperar la transmisión completa de la RÁFAGA (4 bytes * 1600 ns = 6400 ns)
    // *** Lectura Rápida para Receptor ***
    // Insertamos una lectura (rd) cada vez que el byte 'sale' del registro de desplazamiento del TX.
    // Esto simula que la CPU lee el dato RX *justo* antes de que el siguiente byte
    // de la ráfaga lo reemplace en el RBR (si la lógica del RX no lo evita).
    #1600; // Primer byte ('A') recibido
    rd = 1; #10 rd = 0;
    #1590; 
    
    #1600; // Segundo byte ('B') recibido
    rd = 1; #10 rd = 0;
    #1590; 
    
    #1600; // Tercer byte ('C') recibido
    rd = 1; #10 rd = 0;
    #1590; 
    
    #1600; // Cuarto byte ('D') recibido
    rd = 1; #10 rd = 0;


    // 5. FASE MODO NORMAL FINAL (TX de 1 byte)
    // Regresar a Modo Normal (MODE=0) y enviar 'Z' (0x5A)
    wrbaud = 1; 
    // MODO NORMAL (d[31]=0) + Divisor (T_DIVIDER=7) = 32'h00000007
    d = {32'h00000000 | T_DIVIDER}; 
    #20 wrbaud = 0;
    $display("@%0t: Configurado: MODO NORMAL FINAL (d=%h).", $time, d);
    
    #50;
    // Enviar 'Z' (0x5A)
    wrtx = 1; d = 32'h0000005A; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'Z' (Modo Normal Final).", $time);

    // Esperar recepción y última lectura
    #1600;
    rd = 1; #10 rd = 0;

    // Finalización de la simulación
	# 3000 $finish;
end

endmodule
