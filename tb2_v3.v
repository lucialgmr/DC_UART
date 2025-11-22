/// copiar y pegar esto en tb.v cuando se pruebe uartb en system.v
//////COMANDOS TERMINAL: 
//riscv64-unknown-elf-as Firmware/start.S -o start.o
//riscv64-unknown-elf-ld start.o -Ttext=0x0 -o prog.elf
//riscv64-unknown-elf-objcopy -O verilog prog.elf rom.hex
//iverilog -o simv tb.v system.v uart.v uart_burst.v laRVa.v
//vvp simv
//gtkwave waves.vcd
//////
`timescale 1ns/1ps

module tb;

//-----------------------------------------------------
// Señales del testbench
//-----------------------------------------------------
reg clk;                      // reloj principal
reg reset;                    // reset del sistema
wire txd;                     // UART0 TX
reg  rxd;                     // UART0 RX (no se usa en este test)
wire txd_b0;                  //changed //"Salida serie de UARTB0"
reg  rxd_b0;                  //changed //"Entrada serie de UARTB0 (loopback)"

//-----------------------------------------------------
// Instancia del sistema completo
//-----------------------------------------------------
SYSTEM uut (
    .clk(clk),
    .reset(reset),
    .rxd(rxd),
    .txd(txd),
    .salida()
);

//-----------------------------------------------------
// LOOPBACK UARTB0 (txd_b0 → rxd_b0)
//-----------------------------------------------------
//changed //"Conectamos físicamente TXD_B0 con RXD_B0"
//changed //"Esto permite comprobar que lo que se envía se recibe"
assign rxd_b0 = txd_b0;


//-----------------------------------------------------
// Generación del reloj: 25 MHz (periodo = 40 ns)
//-----------------------------------------------------
initial begin
    clk = 0;
    forever #20 clk = ~clk;   //changed //"25 MHz clock"
end


//-----------------------------------------------------
// Reset inicial
//-----------------------------------------------------
initial begin
    reset = 1;                //changed //"Activamos reset global"
    rxd   = 1;                // Mantener RX en alto (estado idle)
    #200;
    reset = 0;                //changed //"Quitamos reset"
end


//-----------------------------------------------------
// Dump de señales para GTKWave
//-----------------------------------------------------
initial begin
    $dumpfile("waves.vcd");       //changed //"Nombre del archivo de ondas"
    $dumpvars(0, tb);             //changed //"Volcar todas las señales del testbench"
end


//-----------------------------------------------------
// Tiempo máximo de simulación
//-----------------------------------------------------
initial begin
    #500000;                  //changed //"Duración de la simulación (ajustable)"
    $display("FIN DE SIMULACION");
    $finish;
end

endmodule
