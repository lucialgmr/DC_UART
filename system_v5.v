//--------------------------------------------------------------------
// SYSTEM: LaRVa RISC-V SoC
// Versión con UARTB0 integrada (modo normal + ráfaga)
//--------------------------------------------------------------------

`include "laRVa.v"
`include "uart.v"
`include "uart_burst.v"

module SYSTEM (
    input clk,        // reloj principal
    input reset,      // reset global activo alto
    input  rxd,       // UART0 RX
    output txd,       // UART0 TX
    output [7:0] salida
);

//-------------------------------------------------------------
// Clock
//-------------------------------------------------------------
wire cclk;
assign cclk = clk;

reg [7:0] outreg;
assign salida = outreg;

//-------------------------------------------------------------
// CPU
//-------------------------------------------------------------
wire [31:0] ca;
wire [31:0] cdo;
wire [31:0] cdi;
wire [3:0]  mwe;
wire irq;
wire [31:2] ivector;
wire trap;

laRVa cpu(
    .clk     (cclk),
    .reset   (reset),
    .addr    (ca[31:2]),
    .wdata   (cdo),
    .wstrb   (mwe),
    .rdata   (cdi),
    .irq     (irq),
    .ivector (ivector),
    .trap    (trap)
);

//-------------------------------------------------------------
// RAM interna (8KB)
//-------------------------------------------------------------
wire ramcs = (ca[31:13] == 19'b0);
wire [10:0] ra = ca[12:2];
wire [31:0] mdo;

ram32 ram0(
    .clk       (cclk),
    .re        (ramcs),
    .wrlanes   (ramcs ? mwe : 4'b0000),
    .addr      (ra),
    .data_read (mdo),
    .data_write(cdo)
);

