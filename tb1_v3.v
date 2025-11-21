//-------------------------------------------------------------------
//-- Testbench para UARTB_CORE (Modo normal, ráfaga y loopback)
//-------------------------------------------------------------------

`timescale 1ns/10ps
`include "uart_burst.v"

module tb;

//----------------------------------------------------------
// Señales del DUT
//----------------------------------------------------------
reg        clk   = 0;
reg        rxd   = 1;
reg        wrtx  = 0;
reg        wrbaud= 0;
reg [31:0] d     = 0;
reg        rd    = 0;

wire       txd;
wire       tend;
wire       thre;
wire [7:0] q;
wire       dv;
wire       fe;
wire       ove;

//----------------------------------------------------------
// Variables de tiempo (ANTES eran localparam)
//----------------------------------------------------------
integer divider_value;
integer char_time_ns;

//----------------------------------------------------------
// Instancia del módulo
//----------------------------------------------------------
UARTB_CORE dut (
    .txd   (txd),
    .tend  (tend),
    .thre  (thre),
    .d     (d),
    .wrtx  (wrtx),
    .wrbaud(wrbaud),
    .q     (q),
    .dv    (dv),
    .fe    (fe),
    .ove   (ove),
    .rxd   (rxd),
    .rd    (rd),
    .clk   (clk)
);

//----------------------------------------------------------
// LOOPBACK: txd -> rxd
//----------------------------------------------------------
always @(txd) begin
    #1 rxd = txd;
end

//----------------------------------------------------------
// Clock 50 MHz
//----------------------------------------------------------
always #10 clk = ~clk;

//----------------------------------------------------------
// TAREAS
//----------------------------------------------------------
task send_byte_normal;
    input [7:0] data;
begin
    #4    d    = {24'h0, data};
	wrtx = 1;
    #20 wrtx = 0;
    $display("@%0t: TX NORMAL -> %02h", $time, data);
end
endtask

task send_word_burst;
    input [31:0] data;
begin
    d    = data;
    wrtx = 1;
    #20 wrtx = 0;
    $display("@%0t: TX BURST -> %08h", $time, data);
end
endtask

task uart_read;
begin
    rd = 1;
    #20 rd = 0;
    if (dv)
        $display("@%0t: RX = %02h (DV=1)", $time, q);
    else
        $display("@%0t: RX leído sin dato válido", $time);
end
endtask

//----------------------------------------------------------
// ESTÍMULOS
//----------------------------------------------------------
initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);

    //------------------------------------------------------
    // Inicializar tiempos sustituyendo localparam
    //------------------------------------------------------
    divider_value = 7;
    char_time_ns  = 1600;  // 8 ciclos * 20ns * 10 bits

    $display("=== INICIO SIMULACIÓN UART ===");

    //------------------------------------------------------
    // Configurar BRG: divisor=7, modo normal (bit31=0)
    //------------------------------------------------------
    #50;
    wrbaud = 1;
    d      = 32'h00000007;
    #20 wrbaud = 0;
    $display("@%0t: Config -> Modo NORMAL, divisor=7", $time);

    //------------------------------------------------------
    // Enviar algunos bytes en modo normal
    //------------------------------------------------------
    send_byte_normal(8'h41);
    #(char_time_ns);
    uart_read();

    send_byte_normal(8'h42);
    #(char_time_ns/2);

    //------------------------------------------------------
    // Cambiar a MODO BURST antes de terminar
    //------------------------------------------------------
    wrbaud = 1;
    d      = 32'h80000007;  // bit31=1 -> modo ráfaga
    #20 wrbaud = 0;
    $display("@%0t: Config -> Modo BURST", $time);

    #(char_time_ns/2);

    //------------------------------------------------------
    // Enviar palabras de 32 bits en ráfaga
    //------------------------------------------------------
    //send_word_burst(32'h44434241); // "ABCD"
    //send_word_burst(32'h33323130); // "0123"
    send_word_burst(32'h616C6F68); // "hola"

    // Leer 8 bytes (puedes aumentar si quieres)
    repeat(8) begin
        #(char_time_ns);
        uart_read();
    end

    //------------------------------------------------------
    // Volver a modo NORMAL
    //------------------------------------------------------
    #(char_time_ns);
    wrbaud = 1;
    d      = 32'h00000007;
    #20 wrbaud = 0;
    $display("@%0t: Config -> Modo NORMAL otra vez", $time);

    send_byte_normal(8'h5A); // 'Z'
    #(char_time_ns);
    uart_read();

    //------------------------------------------------------
    // Fin
    //------------------------------------------------------
    #1000;
    $display("=== FIN SIMULACIÓN ===");
    $finish;
end

endmodule

