//--------------------------------------------------------------------
// SYSTEM: LaRVa RISC-V SoC
// Versión CORRECTA con UARTB0 integrada (modo normal + ráfaga)
//--------------------------------------------------------------------

`include "laRVa.v"
`include "uart.v"
`include "uart_burst.v"

module SYSTEM (
    input clk,        // 25 MHz
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
wire iocs = (ca[31:29] == 3'b111);

wire uartcs    = iocs & (ca[7:5] == 3'b000);   // UART0
wire outcs     = iocs & (ca[7:5] == 3'b010);
wire uartb0cs  = iocs & (ca[7:5] == 3'b100);   // UARTB0 //changed //"nuevo periférico"
wire irqcs     = iocs & (ca[7:5] == 3'b111);

//-------------------------------------------------------------
// Multiplexor lectura IO (iodo)
//-------------------------------------------------------------
reg [31:0] iodo;
always @(*) begin
    casex (ca[7:2])
        // UART0 ---------------------
        6'b000000: iodo <= {24'hx, uart_do};
        6'b000001: iodo <= {27'hx, ove, fe, tend, thre, dv};

        // UARTB0 -------------------- //changed
        6'b100000: iodo <= {24'hx, uartb0_do};                    // RX_data
        6'b100001: iodo <= {27'hx, ove_b0, fe_b0, tend_b0,        // FLAGS
                                   thre_b0, dv_b0};

        // TIMER (0xE0000060) --------
        6'b011xxx: iodo <= tcount;

        // IRQEN ---------------------
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

assign rxd_b0 = txd_b0;   //changed //"loopback para simulación"

assign uwrtx_b0   = uartb0cs & (~ca[2]) & mwe[0];            //changed
assign urd_b0     = uartb0cs & (~ca[2]) & (mwe==4'b0000);    //changed
assign uwrbaud_b0 = uartb0cs &  ca[2]   & mwe[0] & mwe[1];   //changed

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
    if (reset) tcount <= 0;
    else       tcount <= tcount + 1;

//-------------------------------------------------------------
// VIC – Controlador de interrupciones
//-------------------------------------------------------------
reg [4:0] irqen;

always @(posedge cclk or posedge reset)
    if (reset)
        irqen <= 0;
    else if (irqcs & (~ca[4]) & mwe[0])
        irqen <= cdo[4:0];

// Vectores
reg [31:2] irqvect [0:4];
always @(posedge cclk or posedge reset) begin
    if (reset) begin
        irqvect[0] <= 0;
        irqvect[1] <= 0;
        irqvect[2] <= 0;
        irqvect[3] <= 0;
        irqvect[4] <= 0;
    end else begin
        // Vectores 0–3 en 0xF0–0xFC
        if (irqcs & ca[4] & (mwe==4'b1111))
            irqvect[ca[3:2]] <= cdo[31:2];
        // Vector 4 en 0xE4
        if (irqcs & (~ca[4]) & (ca[3:2]==2'b01) & (mwe==4'b1111))
            irqvect[4] <= cdo[31:2];
    end
end

// Peticiones
wire [4:0] irqpen;
assign irqpen[0] = irqen[0] & dv;
assign irqpen[1] = irqen[1] & thre;
assign irqpen[2] = irqen[2] & dv_b0;
assign irqpen[3] = irqen[3] & thre_b0;
assign irqpen[4] = 1'b0;

// Prioridad
reg [2:0] vecn;
always @(*) begin
    if      (trap)      vecn = 0;
    else if (irqpen[0]) vecn = 1;
    else if (irqpen[1]) vecn = 2;
    else if (irqpen[2]) vecn = 3;
    else if (irqpen[3]) vecn = 4;
    else                vecn = 0;
end

assign ivector = irqvect[vecn];
assign irq = (irqpen != 0) | trap;

//-------------------------------------------------------------
// OUTREG
//-------------------------------------------------------------
reg [7:0] outreg;

always @(posedge cclk or posedge reset)
    if (reset)
        outreg <= 0;
    else if (outcs & mwe[0])
        outreg <= cdo[7:0];

endmodule
