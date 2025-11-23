`timescale 1ns/1ps

`include "system.v"

module tb;

reg clk;
reg reset;
reg rxd;
wire txd;
wire [7:0] salida;

SYSTEM uut (
    .clk    (clk),
    .reset  (reset),
    .rxd    (rxd),
    .txd    (txd),
    .salida (salida)
);

// Reloj 25 MHz
initial begin
    clk = 1'b0;
    forever #20 clk = ~clk;
end

// Reset con mensajes por consola
initial begin
    $display("TB: inicio simulacion en t=%0t", $time);
    reset = 1'b1;
    rxd   = 1'b1;         // UART idle
    #200;
    $display("TB: desactivando reset en t=%0t", $time);
    reset = 1'b0;
    #2000000;
    $display("TB: FIN SIMULACION en t=%0t", $time);
    $finish;
end

// Volcado de ondas
initial begin
    $dumpfile("waves.vcd");
    $dumpvars(0, tb);
end

endmodule
