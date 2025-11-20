//-------------------------------------------------------------------\
//-- Test Bench ADAPTADO para UARTB_CORE (Modo Normal, Modo Ráfaga y Loopback)
//-------------------------------------------------------------------\

`timescale 1ns/10ps
`include "uart_burst.v"

module tb();

//-- Registos con señales de entrada
reg clk=0;
reg rxd=1;        // Entrada RX (inicializada a IDLE=1)
reg wrtx=0;       // Pulso de escritura TX
reg wrbaud=0;     // Pulso de escritura BRG/Mode
reg[31:0] d;      // Datos de 16 bits (8 bits para TX, 9 bits para BRG/Mode)
reg rd = 0;       // Pulso de lectura RX (borra DV)

// Señal de salida TX del módulo
wire txd;

UARTB_CORE myUART(
  .txd(txd),
  //... otras salidas de flag (tend, thre, dv, etc.) - Si existen, se visualizan.
  .d(d),          // Datos TX/BRG
  .wrtx(wrtx),    // Escritura en TX (asumimos que en el modo Ráfaga, d[31:0] es el bus de 32 bits)
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
    
    $display("--- Testbench UARTB Iniciado ---");

    // 1. CONFIGURACIÓN INICIAL: DIVIDER=7 y MODE=0 (Normal)
    // El bit de modo se asume en d[9], y el divisor en d[8:0].
    #10;
    wrbaud = 1; 
    // d[9]=0 (Normal), d[8:0]=7 (Divisor de 8) -> 16'h0007
    d = {7'b0, 1'b0, 8'd7}; 
    #20 wrbaud = 0;
    $display("@%0t: Configurado Modo Normal (MODE=0), Divisor=7.", $time);


    // 2. FASE MODO NORMAL (TX de 1 byte)
    // Se enviarán 'A', 'B', 'C'
    
    // Enviar 'A' (0x41)
    #100 wrtx = 1; d = 16'h0041; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'A' (Modo Normal).", $time);
    #100; // Espera un poco

    // Enviar 'B' (0x42) - Mismo modo
    wrtx = 1; d = 16'h0042; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'B' (Modo Normal).", $time);
    #100; // Espera un poco

    // 3. CONMUTACIÓN DURANTE LA TRANSMISIÓN: Modo Ráfaga (MODE=1)
    // Asumimos que la transmisión de 'B' sigue en curso (en el registro de desplazamiento)
    #50;
    wrbaud = 1; 
    // d[9]=1 (Ráfaga), d[8:0]=7 (Divisor de 8) -> 16'h0207
    d = {6'b0, 1'b1, 9'd7}; 
    #10 wrbaud = 0;
    $display("@%0t: Conmutado a Modo Ráfaga (MODE=1) y divisor 7.", $time);
    #50;

    // 4. FASE MODO RÁFAGA (TX de 32 bits)
    // Enviar "ABCD" (0x44434241 - Little Endian)
    
    // Simulando el valor completo de 32 bits que vendría del bus
    reg [31:0] data32;
    data32 = 32'h44434241; // D, C, B, A (en el bus de 32 bits)

    wrtx = 1; 

    // Escribimos el dato de 32 bits (ABCD)
	d[31:0] = data32[31:0];
    wrtx = 1; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando Ráfaga 1 (ABCD, 32-bit).", $time);
    
    #1000; // Esperar a que gran parte de la ráfaga haya salido

    // 5. FASE MODO NORMAL FINAL (TX de 1 byte)
    // Regresar a Modo Normal y enviar 'Z'
    wrbaud = 1; 
    // d[9]=0 (Normal), d[8:0]=7 (Divisor de 8) -> 16'h0007
    d = {7'b0, 1'b0, 9'd7}; 
    #10 wrbaud = 0;
    $display("@%0t: Conmutado de nuevo a Modo Normal (MODE=0).", $time);
    
    #50;
    // Enviar 'Z' (0x5A)
    wrtx = 1; d = 16'h005A; 
    #10 wrtx = 0; 
    $display("@%0t: Enviando 'Z' (Modo Normal Final).", $time);

    // Finalización de la simulación
	# 3000 $finish;
end

endmodule
