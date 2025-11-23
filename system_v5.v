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

//-------------------------------------------------------------
// IO Chip-select
//-------------------------------------------------------------
wire iocs = (ca[31:29] == 3'b111);   // zona 0xE0000000

wire uartcs    = iocs & (ca[7:5] == 3'b000); // UART0
wire outcs     = iocs & (ca[7:5] == 3'b010); // GPO
wire uartb0cs  = iocs & (ca[7:5] == 3'b100); // UARTB0
wire irqcs     = iocs & (ca[7:5] == 3'b111); // VIC

//-------------------------------------------------------------
// Multiplexor lectura IO (iodo)
//-------------------------------------------------------------
reg [31:0] iodo;

always @(*) begin
    casex (ca[7:2])
        // UART0 -------------------------------------------------
        6'b000000: iodo <= {24'hx, uart_do};                   // RX_data
        6'b000001: iodo <= {27'hx, ove, fe, tend, thre, dv};   // FLAGS

        // UARTB0 ------------------------------------------------
        6'b100000: iodo <= {24'hx, uartb0_do};                 // RX_data
        6'b100001: iodo <= {27'hx, ove_b0, fe_b0, tend_b0,
                                   thre_b0, dv_b0};            // FLAGS

        // TIMER -------------------------------------------------
        6'b011xxx: iodo <= tcount;

        // IRQEN -------------------------------------------------
        6'b111xxx: iodo <= {28'hx, irqen};

        default:   iodo <= 32'hxxxxxxxx;
    endcase
end

assign cdi = ramcs ? mdo : iodo;

//-------------------------------------------------------------
// UART0 (original)
//-------------------------------------------------------------
parameter BAUDBITS = 12;

wire [7:0] uart_do;
wire dv, fe, ove, tend, thre;
wire uwrtx, urd, uwrbaud;

assign uwrtx   = uartcs & (~ca[2]) & mwe[0];
assign urd     = uartcs & (~ca[2]) & (mwe==4'b0000);
assign uwrbaud = uartcs &  ca[2]   & mwe[0] & mwe[1];

UART_CORE #(.BAUDBITS(BAUDBITS)) uart0 (
    .clk    (cclk),
    .txd    (txd),
    .rxd    (rxd),
    .d      (cdo[15:0]),
    .wrtx   (uwrtx),
    .wrbaud (uwrbaud),
    .rd     (urd),
    .q      (uart_do),
    .dv     (dv),
    .fe     (fe),
    .ove    (ove),
    .tend   (tend),
    .thre   (thre)
);

//-------------------------------------------------------------
// UARTB0 (nueva, con modo ráfaga)
//-------------------------------------------------------------
wire [7:0] uartb0_do;
wire dv_b0, fe_b0, ove_b0, tend_b0, thre_b0;
wire uwrtx_b0, urd_b0, uwrbaud_b0;
wire txd_b0, rxd_b0;

assign rxd_b0 = txd_b0;      // loopback para simulación

assign uwrtx_b0   = uartb0cs & (~ca[2]) & mwe[0];          // TX_data
assign urd_b0     = uartb0cs & (~ca[2]) & (mwe==4'b0000);  // RX_data
assign uwrbaud_b0 = uartb0cs &  ca[2]   & mwe[0] & mwe[1]; // DIVIDER/MODE

UARTB_CORE #(.BAUDBITS(BAUDBITS)) uartb0 (
    .clk    (cclk),
    .txd    (txd_b0),
    .rxd    (rxd_b0),
    .d      (cdo),
    .wrtx   (uwrtx_b0),
    .wrbaud (uwrbaud_b0),
    .rd     (urd_b0),
    .q      (uartb0_do),
    .dv     (dv_b0),
    .fe     (fe_b0),
    .ove    (ove_b0),
    .tend   (tend_b0),
    .thre   (thre_b0)
);

//-------------------------------------------------------------
// TIMER
//-------------------------------------------------------------
reg [31:0] tcount;

always @(posedge cclk or posedge reset)
    if (reset) tcount <= 32'h00000000;
    else       tcount <= tcount + 1;

//-------------------------------------------------------------
// VIC – Controlador de interrupciones
//-------------------------------------------------------------
reg [4:0] irqen;

always @(posedge cclk or posedge reset) begin
    if (reset)
        irqen <= 5'b00000;
    else if (irqcs & (~ca[4]) & mwe[0])
        irqen <= cdo[4:0];
end

reg [31:2] irqvect [0:4];

always @(posedge cclk or posedge reset) begin
    if (reset) begin
        irqvect[0] <= 30'h0;
        irqvect[1] <= 30'h0;
        irqvect[2] <= 30'h0;
        irqvect[3] <= 30'h0;
        irqvect[4] <= 30'h0;
    end else begin
        // vectores 0..3 → 0xE00000F0..FC
        if (irqcs & ca[4] & (mwe==4'b1111))
            irqvect[ca[3:2]] <= cdo[31:2];
        // vector 4 → 0xE00000E4
        if (irqcs & (~ca[4]) & (ca[3:2]==2'b01) & (mwe==4'b1111))
            irqvect[4] <= cdo[31:2];
    end
end

wire [4:0] irqpen;
assign irqpen[0] = irqen[0] & dv;
assign irqpen[1] = irqen[1] & thre;
assign irqpen[2] = irqen[2] & dv_b0;
assign irqpen[3] = irqen[3] & thre_b0;
assign irqpen[4] = 1'b0;

reg [2:0] vecn;

always @(*) begin
    if      (trap)      vecn = 3'd0;
    else if (irqpen[0]) vecn = 3'd1;
    else if (irqpen[1]) vecn = 3'd2;
    else if (irqpen[2]) vecn = 3'd3;
    else if (irqpen[3]) vecn = 3'd4;
    else                vecn = 3'd0;
end

assign ivector = irqvect[vecn];
assign irq     = (irqpen != 5'b00000) | trap;

//-------------------------------------------------------------
// OUTREG
//-------------------------------------------------------------
always @(posedge cclk or posedge reset)
    if (reset)
        outreg <= 8'h00;
    else if (outcs & mwe[0])
        outreg <= cdo[7:0];

endmodule

//-------------------------------------------------------------
// RAM32 (sin cambios)
//-------------------------------------------------------------
module ram32
 ( input         clk,
   input         re,
   input  [3:0]  wrlanes,
   input  [10:0] addr,
   output [31:0] data_read,
   input  [31:0] data_write
 );

reg [31:0] ram_array [0:2047];
reg [31:0] data_out;

assign data_read = data_out;

always @(posedge clk) begin
    if (wrlanes[0]) ram_array[addr][7:0]   <= data_write[7:0];
    if (wrlanes[1]) ram_array[addr][15:8]  <= data_write[15:8];
    if (wrlanes[2]) ram_array[addr][23:16] <= data_write[23:16];
    if (wrlanes[3]) ram_array[addr][31:24] <= data_write[31:24];
end

always @(posedge clk) begin
    if (re) data_out <= ram_array[addr];
end

initial begin
`ifdef SIMULATION
    $readmemh("rom.hex", ram_array);
`else
    $readmemh("rand.hex", ram_array);
`endif
end

endmodule

