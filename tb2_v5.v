`timescale 1ns/1ps

// Activamos un define opcional para distinguir simulación (si lo necesitas)
`define SIMULATION

// Incluimos el sistema completo
`include "system.v"

module tb;

//-----------------------------------------------------
// Señales del testbench
//-----------------------------------------------------
reg clk;
reg reset;        // reset global activo alto
reg rxd;          // línea RX de la UART0 (no se usa en la prueba de UARTB0)
wire txd;         // línea TX de la UART0
wire [7:0] salida;

//-----------------------------------------------------
// Instancia del sistema LaRVa
//-----------------------------------------------------
SYSTEM uut (
    .clk    (clk),
    .reset  (reset),
    .rxd    (rxd),
    .txd    (txd),
    .salida (salida)
);

//-----------------------------------------------------
// Generación de reloj: 25 MHz (periodo = 40 ns)
//-----------------------------------------------------
initial begin
    clk = 1'b0;
    forever #20 clk = ~clk;   // 25 MHz
end

//-----------------------------------------------------
// Reset inicial y línea RX en estado idle
//-----------------------------------------------------
initial begin
    reset = 1'b1;  // activamos reset
    rxd   = 1'b1;  // UART en reposo (nivel alto)
    #200;          // 200 ns de reset
    reset = 1'b0;  // desactivamos reset → arranca la CPU
end

//-----------------------------------------------------
// Volcado de ondas y fin de simulación
//-----------------------------------------------------
initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb);   // volcar todas las señales del testbench

    #2000000;           // tiempo total de simulación (~2 ms)
    $display("FIN DE LA SIMULACION");
    $finish;
end

endmodule
