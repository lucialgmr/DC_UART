//--------------------------------------------------------------------
// RISC-V things cambios 20/11
// by Jesús Arias (2022)
//--------------------------------------------------------------------
/*
    Description:
    A LaRVA RISC-V system with 8KB of internal memory, and one UART
    
    Memory map:
    
    0x00000000 to 0x00001FFF    Internal RAM (with inital contents)
    0x00002000 to 0x1FFFFFFF    the same internal RAM repeated each 8KB
    0x20000000 to 0xDFFFFFFF       xxxx
    0xE0000000 to 0xE00000FF    IO registers
    0xE0000100 to 0xFFFFFFFF    the same IO registers repeated each 256B

    IO register map (all registers accessed as 32-bit words):
    
      address  |      WRITE        |      READ
    -----------|-------------------|---------------
    0xE0000000 | UART TX data      |  UART RX data
    0xE0000004 | UART Baud Divider |  UART flags
               |                   |
    0xE0000040 | OPUTPUT_REG       |  OUTPUT_REG  //changed_2310
               |                   |
    0xE0000060 |                   |  Cycle counter
               |                   |
    0xE00000E0 | Interrupt Enable  |  Interrupt enable
    0xE00000F0 | IRQ vector 0 Trap |
    0xE00000F4 | IRQ vector 1 RX   |
    0xE00000F8 | IRQ vector 2 TX   |
    0xE00000FC | IRQ vector 3 IGPO |  //changed_2310
    
    UART Baud Divider: Baud = Fcclk / (DIVIDER+1) , with DIVIDER >=7
    
    UART FLAGS:    bits 31-5  bit 4  bit 3 bit 2 bit 1 bit 0
                     xxxx      OVE    FE    TEND  THRE   DV
        DV:   Data Valid (RX complete if 1. Cleared reading data register)
        THRE: TX Holding register empty (ready to write to data register if 1)
        TEND: TX end (holding reg and shift reg both empty if 1)
        FE:   Frame Error (Stop bit received as 0 if FE=1)
        OVE:  Overrun Error (Character received when DV was still 1)
        (DV and THRE assert interrupt channels #4 and #5 when 1)

    Interrupt enable: Bits 1-0
        bit 0: Enable UART RX interrupt if 1
        bit 1: Enable UART TX interrupt if 1
        bit 2: Enable GPO interrupt if 1 (detection of 0x00FF_00FF) //changed_2310
         
*/

`include "laRVa.v"
`include "uart_burst.v"
`include "uart.v"

module SYSTEM (
    input clk,        // Main clock input 25MHz
    input reset,    // Global reset (active high)

    input    rxd,    // UART
    output     txd,
    
    output [31:0] salida,  // changed_2710
    
    output sck,        // SPI
    output mosi,
    input  miso,
    output fssb    // Flash CS

);

wire        cclk;    // CPU clock
assign    cclk=clk;

assign salida=outreg; // changed_2710

///////////////////////////////////////////////////////
////////////////////////// CPU ////////////////////////
///////////////////////////////////////////////////////

wire [31:0]    ca;        // CPU Address
wire [31:0]    cdo;    // CPU Data Output
wire [3:0]    mwe;    // Memory Write Enable (4 signals, one per byte lane)
wire irq;
wire [31:2]ivector;    // Where to jump on IRQ
wire trap;            // Trap irq (to IRQ vector generator)

laRVa cpu (
        .clk     (cclk ),
        .reset   (reset),
        .addr    (ca[31:2] ),
        .wdata   (cdo  ),
        .wstrb   (mwe  ),
        .rdata   (cdi  ),
        .irq     (irq  ),
        .ivector (ivector),
        .trap    (trap)
    );

 
///////////////////////////////////////////////////////
///// Memory mapping
wire iramcs;
wire iocs;
// Internal RAM selected in lower 512MB (0-0x1FFFFFFF)
assign iramcs = (ca[31:29]==3'b000);
// IO selected in last 512MB (0xE0000000-0xFFFFFFFF)
assign iocs   = (ca[31:29]==3'b111);

// Input bus mux
reg [31:0]cdi;    // Not a register
always@*
 casex ({iocs,iramcs})
        2'b01: cdi<=mdo;
        2'b10: cdi<=iodo;
        default: cdi<=32'hxxxxxxxx;
 endcase

///////////////////////////////////////////////////////
//////////////////// internal memory //////////////////
///////////////////////////////////////////////////////
wire [31:0]    mdo;    // Output data
ram32     ram0 ( .clk(~cclk), .re(iramcs), .wrlanes(iramcs?mwe:4'b0000),
            .addr(ca[12:2]), .data_read(mdo), .data_write(cdo) );

//////////////////////////////////////////////////
////////////////// Peripherals ///////////////////
//////////////////////////////////////////////////
reg [31:0]tcount=0;
always @(posedge clk) tcount<=tcount+1;

wire uartcs;    // UART    at offset 0x00
// wire spics;  // SPI at offset 0x20
wire outcs;
// outreg at offset 0x40 changed_2310
wire irqcs;        // IRQEN at offset 0xE0
                //         ...
                // other at offset 0xE0
wire uartb0cs; //(modificado1511) Chip select para UARTB a offset 0x80
assign uartcs = iocs&(ca[7:5]==3'b000);
//assign spics  = iocs&(ca[7:5]==3'b001);
assign outcs  = iocs&ca[7:5]==3'b010;  //changed_2310
assign uartb0cs = iocs&(ca[7:5]==3'b100); //(modificado1511) UARTB_CORE en 0xE000_0080
assign irqcs  = iocs&(ca[7:5]==3'b111);
// Peripheral output bus mux
reg [31:0]iodo;    // Not a register
always@*
 casex (ca[7:2])
    6'b000xx0: iodo<={24'hx,uart_do};
    6'b000xx1: iodo<={27'hx,ove,fe,tend,thre,dv};
    6'b100000:
		if(mode == 1'b0)
			iodo<={24'hx,uartb0_do}; 
		else 
			iodo<={uartb0_do};//(modificado1511) Lectura de RX_data de UARTB0 (0x80)
    6'b100001: iodo<={27'hx,ove_b0,fe_b0,tend_b0,thre_b0,dv_b0}; //(modificado1511) Lectura de FLAGS de UARTB0 (0x84)
    6'b011xxx: iodo<=tcount;
    6'b111xxx: iodo<={28'hx,irqen};
default: iodo<=32'hxxxxxxxx; //(modificado1511) Mantenida como default
 endcase

/////////////////////////////
// UART

wire tend,thre,dv,fe,ove; // Flags
wire [7:0] uart_do;    // RX output data
wire uwrtx;            // UART TX write
wire urd;
// UART RX read (for flag clearing)
wire uwrbaud;        // UART BGR write

// (modificado1511) Nuevas señales para UARTB
wire tend_b0, thre_b0, dv_b0, fe_b0, ove_b0; // Flags UARTB
wire [7:0] uartb0_do; // RX output data UARTB
wire uwrtx_b0; // UARTB TX write
wire urd_b0; // UARTB RX read
//wire uwrbaud_b0; // UARTB BGR/MODE write
wire txd_b0, rxd_b0; //(modificado1511) Líneas serie para UARTB
assign rxd_b0 = txd_b0; //(modificado1511) Loopback para simulación

// Register mapping UART0
// Offset 0: write: TX Holding reg
// Offset 0: read strobe: Clear DV, OVE (also reads RX data buffer)
// Offset 1: write: BAUD divider

parameter BAUDBITS = 12;

assign uwrtx   = uartcs & (~ca[2]) & mwe[0];
assign uwrbaud = uartcs & ( ca[2]) & mwe[0] & mwe[1]; // UART0 a 16 bits
assign urd     = uartcs & (~ca[2]) & (mwe==4'b0000); // Clear DV, OVE flgas

// (modificado1511) Register mapping UARTB0 (ca[3:2] para 0x80 y 0x84)
// Dirección Base (0x80): Escritura (wrtx) para TX_data (32 bits), Lectura (urd_b0) para RX_data (limpia flags)
if(mode==1'b0)
	assign uwrtx_b0   = uartb0cs & (~ca[2]) & (mwe!=4'b0000); //(modificado1511) wrtx si se está en 0x80 y se escribe algo
else
	assign uwrtx_b0   = uartb0cs & (~ca[2]) & (mwe==4'b1111); //(modificado1511) wrtx si se está en 0x80 y se escribe algo
assign urd_b0     = uartb0cs & (~ca[2]) & (mwe==4'b0000); //(modificado1511) urd si se está en 0x80 y se lee
// Dirección Base+4 (0x84): Escritura (wrbaud_b0) para DIVIDER/MODE (32 bits), Lectura (gestionada por iodo)
assign uwrbaud_b0 = uartb0cs & (ca[2]) & mwe[0] & mwe[1]; //(modificado1511) wrbaud si se está en 0x84 y se escribe algo (PORQUE OCUPA BAUDBITS) QUE SON 8+1


UART_CORE #(.BAUDBITS(12)) uart0 ( .clk(cclk), .txd(txd), .rxd(rxd),
    .d(cdo[15:0]), .wrtx(uwrtx), .wrbaud(uwrbaud),. rd(urd), .q(uart_do),
    .dv(dv), .fe(fe), .ove(ove), .tend(tend), .thre(thre) );
    
// (modificado1511) Instanciación de UARTB_CORE
UARTB_CORE #(.BAUDBITS(12)) uartb0 (
    .clk(cclk),
    .txd(txd_b0),
    .rxd(rxd_b0),
    .d(cdo),          // Conexión del bus de datos completo (32 bits)
    .wrtx(uwrtx_b0),
    .wrbaud(uwrbaud_b0),
    .rd(urd_b0),
    .q(uartb0_do),
	.mode(modeB),
    .dv(dv_b0),
    .fe(fe_b0),
    .ove(ove_b0),
    .tend(tend_b0),
    .thre(thre_b0)
); //(modificado1511)

//////////////////////////////////////////
//    Interrupt control

// IRQ enable reg
reg [4:0]irqen=0;  //changed_2310 CAMBIADO
always @(posedge cclk or posedge reset) begin
    if (reset) irqen<=0;
else
    if (irqcs & (~ca[4]) &mwe[0]) irqen<=cdo[4:0];  //changed_2310
end

// (modificado1511) Fuentes de IRQ: agrupando DV y THRE de ambas UARTS
//wire irq_rx_all = dv | dv_b0; //(modificado1511) RX pendiente (cualquier UART)
//wire irq_tx_all = thre | thre_b0; //(modificado1511) TX pendiente (cualquier UART)

// IRQ vectors
reg [31:2]irqvect[0:3]; //(modificado1511) Ampliación a 5 vectores (0 a 4) //PONGO 4

//COMPACTO LO DE ABAJO
//reg [31:2]irqvect[0:3];
//always @(posedge cclk) if (irqcs & ca[4] & (mwe==4'b1111)) irqvect[ca[3:2]]<=cdo[31:2];

//no lo acabo de entender
always @(posedge cclk) begin //(modificado1511) Bloque de escritura de vectores
    if (irqcs & ca[4] & (mwe==4'b1111)) begin
        // Se asume que las direcciones F0, F4, F8, FC se usarán para V0-V3, y remapeamos las fuentes:
        if (ca[3:2]==2'b00) irqvect[0]<=cdo[31:2]; //(modificado1511) Vector 0 (Trap)
        else if (ca[3:2]==2'b01) irqvect[1]<=cdo[31:2]; //(modificado1511) Vector 1 (UARTB0 RX)
        else if (ca[3:2]==2'b10) irqvect[2]<=cdo[31:2]; //(modificado1511) Vector 2 (UARTB0 TX)
        else if (ca[3:2]==2'b11) irqvect[3]<=cdo[31:2]; //(modificado1511) Vector 3 (UART0 RX)
    end
    // Se asume que el Vector 4 se mapea en la dirección 0xE000_00EC (irqcs & (~ca[4]) & ca[3:2]=10)
    else if (irqcs & (~ca[4]) & (ca[3:2]==2'b10) & (ca[5]) & (mwe==4'b1111)) begin //(modificado1511) Mapeo para V4 (0xE000_00EC)
        irqvect[4]<=cdo[31:2]; //(modificado1511) Vector 4 (UART0 TX)
    end
end //(modificado1511)

// Enabled IRQs
wire irqrx_group= ( irqen[0]&dv | irqen[1]&dv_b0 );// interrupciones lectura	
wire irqtx_group= ( irqen[3]&thre | irqen[4]&thre_b0);// interrupciones escritura	
wire [1:0] irqpen = {irqtx_group, irqrx_group};	// pending IRQs	

/*
// Priority encoder du
wire [1:0]vecn = trap      ? 2'b00 : (	// ECALL, EBREAK: highest priority
				 irqpen[0] ? 2'b01 : (	// UARTF FULL		//changed_2.2
				 irqpen[1] ? 2'b10 : (	// UART y UARTF RX	//changed_2.2
				 irqpen[2] ? 2'b11 : 	// UART y UARTF TX	//changed_2.2
				 			 2'bxx )));		
assign ivector = irqvect[vecn];
assign irq = (irqpen!=0)|trap;
*/

// (modificado1511) Asignación de flags para el priority encoder (5 fuentes)
// Orden de prioridad (de más alta a más baja): Trap > UARTB0_RX > UARTB0_TX > UART0_RX > UART0_TX > IGPO
/*wire irq_dv_b0_pen = irqen[0]&dv_b0; //(modificado1511)
wire irq_thre_b0_pen = irqen[1]&thre_b0; //(modificado1511)
wire irq_dv_pen = irqen[0]&dv; //(modificado1511)
wire irq_thre_pen = irqen[1]&thre; //(modificado1511)
wire irq_igpo_pen = irqen[2]&IGPO; //(modificado1511)*/

// (modificado1511) Priority encoder (3 bits para 5 vectores: 0 a 4)
/*wire [1:0]vecn_3b_sel = trap ? 3'b00 : ( //(modificado1511) Vector 0: Trap
    irq_dv_b0_pen   ? 3'b01 : ( //(modificado1511) Vector 1: UARTB0 RX
    irq_thre_b0_pen ? 3'b10 : ( //(modificado1511) Vector 2: UARTB0 TX
    irq_dv_pen      ? 3'b11 : ( //(modificado1511) Vector 3: UART0 RX
    irq_thre_pen    ? 3'b100 : ( //(modificado1511) Vector 4: UART0 TX
    irq_igpo_pen    ? 3'b101 :   //(modificado1511) Vector 5: IGPO (Fuera de los 5 vectores)
                    3'bxxx ))))); //(modificado1511)

assign ivector = irqvect[vecn_3b_sel[2:0]]; //(modificado1511) Se usa el resultado de 3 bits para indexar el array
assign irq = (irq_rx_all | irq_tx_all | irq_igpo_pen) | trap; //(modificado1511) IRQ activa si hay alguna interrupción pendiente o Trap
*/
// ... (resto del código del GPO)

/*
// IRQ vectors
always @(posedge cclk) if (irqcs & ca[4] & (mwe==4'b1111)) irqvect[ca[3:2]]<=cdo[31:2];

// Enabled IRQs
wire [2:0]irqpen={irqen[2]&IGPO, irqen[1]&thre, irqen[0]&dv}; //pending IRQS //changed_2310
*/
// Priority encoder
wire [1:0]vecn = trap      ? 2'b00 : (    // ECALL, EBREAK: highest priority
                 irqpen[0] ? 2'b01 : (    // UART RX
                 irqpen[1] ? 2'b10 : (  // UART TX
                 irqpen[2] ? 2'b11 :     // UART IGP0 //changed_2310 ¿¿¿¿¿¿???????????????
                              2'bxx )));
assign ivector = irqvect[vecn];
assign irq = (irqpen!=0)|trap;

/////////////////////////////////////////////////////////////changed_2310
// GPO output reg
/*reg [31:0] outreg;
reg IGPO =0;
wire [3:0] owr;

assign owr={4{outcs}} & mwe;

always@ (posedge clk)
    begin
        outreg[31:24] <= owr[3] ? cdo [31:24] : outreg[31:24];
        outreg[23:16] <= owr[2] ? cdo [23:16] : outreg[23:16];
         outreg[15:8] <= owr[1] ? cdo  [15:8] :  outreg[15:8];
          outreg[7:0] <= owr[0] ? cdo   [7:0] :   outreg[7:0];
    end
    
always@ (posedge clk or posedge reset)
    if (reset || outreg == 32'h00000000)
        IGPO <= 1'b0;
    else if (outreg == 32'h00FF00FF)
        IGPO <= 1'b1;
// end_changed_2310

endmodule    // System

*/
//////////////////////////////////////////////////////////////////////////////
//----------------------------------------------------------------------------
//-- 32-bit RAM Memory with independent byte-write lanes
//----------------------------------------------------------------------------
//////////////////////////////////////////////////////////////////////////////

module ram32
 (    input    clk,
    input    re,
    input    [3:0]    wrlanes,
    input    [10:0]    addr,
    output    [31:0]    data_read,
    input    [31:0]     data_write
 );

reg [31:0] ram_array [0:2047];
reg [31:0] data_out;
        
assign data_read = data_out;
        
always @(posedge clk) begin
    if (wrlanes[0]) ram_array[addr][ 7: 0] <= data_write[ 7: 0];
    if (wrlanes[1]) ram_array[addr][15: 8] <= data_write[15: 8];
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
