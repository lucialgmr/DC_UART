//--------------------------------------------------------------------
// RISC-V things cambios 23/11
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

    IO registers mapping
    
    addr[11:2]
    
    0xE0000000 | UART RX  8 bits |  UART_TX  (UART0)  
    0xE0000004 | UART FLAGS      |  UART_FLAGS
    0xE0000040 | OUTREG          |  OUTPUT_REG              //changed_2310
    0xE0000060 | TIMER           |  TIMER
    0xE0000080 | UARTB0 RX/TX    |  UARTB0 (modo ráfaga)    // UART nueva
    0xE0000084 | UARTB0 FLAGS / DIVIDER+MODE                // UART nueva
    0xE00000E0 | IRQEN           |  Interrupt enable register
    0xE00000E4 | IRQ vector 4    |  UARTB0 TX vector        //changed
    0xE00000F0 | IRQ vector 0    |  TRAP vector
    0xE00000F4 | IRQ vector 1    |  UART0 RX vector
    0xE00000F8 | IRQ vector 2    |  UART0 TX vector
    0xE00000FC | IRQ vector 3    |  UARTB0 RX vector
    
    UART Baud Divider: Baud = Fcclk / (DIVIDER+1) , with DIVIDER >=7
    
    UART FLAGS:    bits 31-5  bit 4  bit 3 bit 2 bit 1 bit 0
                     xxxx      OVE    FE    TEND  THRE   DV
        DV:   Data Valid (RX complete if 1. Cleared reading data register)
        THRE: TX Holding register empty (ready to write to data register if 1)
        TEND: TX end (holding reg and shift reg both empty if 1)
        FE:   Frame Error (Stop bit received as 0 if FE=1)
        OVE:  Overrun Error (Character received when DV was still 1)
        (DV and THRE assert interrupt channels when 1)

    Interrupt enable: Bits 4-0
        bit 0: Enable UART0 RX interrupt if 1
        bit 1: Enable UART0 TX interrupt if 1
        bit 2: Enable UARTB0 RX interrupt if 1
        bit 3: Enable UARTB0 TX interrupt if 1
        bit 4: Reservado (no usado de momento)
*/

`include "laRVa.v"
`include "uart_burst.v"
`include "uart.v"

module SYSTEM (
    input clk,             // Main clock input 25MHz
    input reset,           // Global reset (active high)

    input  rxd,           // UART0 RX
    output txd,           // UART0 TX

    output [31:0] salida   //changed_2710 salida GPO
);

//--------------------------------------------------------------------
// Clock
//--------------------------------------------------------------------
wire cclk;              // CPU clock
assign cclk = clk;

assign salida = outreg; // changed_2710

///////////////////////////////////////////////////////
////////////////////////// CPU ////////////////////////
///////////////////////////////////////////////////////

wire [31:0] ca;      // CPU Address
wire [31:0] cdo;     // CPU Data Output
wire [3:0]  mwe;     // Memory Write Enable (4 signals, one per byte lane)
wire        irq;
wire [31:2] ivector; // Where to jump on IRQ
wire        trap;    // Trap irq (to IRQ vector generator)

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

////////////////////////////////////////////////////////
///////////////////// RAM Block ////////////////////////
////////////////////////////////////////////////////////

wire [31:0] mdo;
wire        iramcs;
wire [10:0] ra;
wire [3:0]  wrlanes;

// Memory write strobe
assign iramcs = (ca[31:29]==3'b000); // lower 512MB (0x00000000 to 0x1FFFFFFF)
assign ra    = ca[12:2];

assign wrlanes = iramcs ? mwe : 4'b0000;

ram32 ram0 (
    .clk       (cclk),
    .re        (iramcs),
    .wrlanes   (wrlanes),
    .addr      (ra),
    .data_read (mdo),
    .data_write(cdo)
);

////////////////////////////////////////////////////////
//////////////////////// IO CS /////////////////////////
////////////////////////////////////////////////////////

wire iocs;
assign iocs = (ca[31:29]==3'b111); // 0xE0000000 to 0xFFFFFFFF

// Input bus mux///////////////////////////////////
reg [31:0]cdi;	// Not a register
always@*
 casex ({iocs,iramcs})
        2'b01: cdi<=mdo; 
        2'b10: cdi<=iodo;
        default: cdi<=32'hxxxxxxxx;
 endcase

//--------------------------------------------------------------
// Chip select de periféricos y multiplexor de lectura (iodo)
//--------------------------------------------------------------
//////////////////////////////////////////////////
////////////////// Peripherals ///////////////////
//////////////////////////////////////////////////
reg [31:0]tcount=0;
always @(posedge clk) tcount<=tcount+1;


wire uartcs;     //changed //"Chip select de la UART original en 0xE000_0000"
//wire spics;   // SPI no usada en esta práctica
wire outcs;      //changed //"Chip select del registro de salida GPO en 0xE000_0040"
wire irqcs;      //changed //"Chip select del controlador de interrupciones (IRQEN/Vectores)"
wire uartb0cs;   //changed //"Chip select de la nueva UARTB0 en 0xE000_0080"

// Chip-selects dentro del espacio de E/S (iocs=1 indica rango 0xE000_0000)
// Se usan los bits ca[7:5] para seleccionar el periférico concreto.
assign uartcs   = iocs & (ca[7:5]==3'b000);       //changed //"Acceso a UART0"
//assign spics  = iocs & (ca[7:5]==3'b001);
assign outcs    = iocs & (ca[7:5]==3'b010);       //changed //"Acceso al registro OUT"
assign uartb0cs = iocs & (ca[7:5]==3'b100);       //changed //"Acceso a UARTB0"
assign irqcs    = iocs & (ca[7:5]==3'b111);       //changed //"Acceso al bloque de interrupciones"

// Multiplexor de lectura del bus de periféricos (iodo)
// Cada rango de direcciones devuelve los datos del periférico correspondiente.
reg [31:0] iodo;                                  //changed //"Dato leído desde periféricos"
always @* begin                                   //changed //"Selección combinacional del origen de iodo"
  casex (ca[7:2])                                 //changed //"Se usan ca[7:2] para discriminar registros de 32 bits"
    // --- UART0 original -----------------------------------------------------
    6'b000xx0: iodo <= {24'hx, uart_do};         //changed //"RX_data UART0 en 0xE000_0000"
    6'b000xx1: iodo <= {27'hx, ove, fe, tend,
                               thre, dv};        //changed //"FLAGS UART0 en 0xE000_0004"

    // --- Nueva UARTB0 -------------------------------------------------------
    6'b100xx0: iodo <= {24'hx, uartb0_do};       //changed //"RX_data UARTB0 en 0xE000_0080"
    6'b100xx1: iodo <= {27'hx, ove_b0, fe_b0,
                               tend_b0, thre_b0,
                               dv_b0};           //changed //"FLAGS UARTB0 en 0xE000_0084"

    // --- Timer e IRQEN ------------------------------------------------------
    6'b011xxx: iodo <= tcount;                   //changed //"Lectura del temporizador en 0xE000_0060"
    6'b111xxx: iodo <= {28'hx, irqen};           //changed //"Lectura del registro IRQEN en 0xE000_00E0"

    default:  iodo <= 32'hxxxxxxxx;              //changed //"Valor indefinido para direcciones no decodificadas"
  endcase                                        //changed
end                                              //changed

/////////////////////////////
// UART
/////////////////////////////

// UART0 original (la que ya incluía el sistema)
wire        tend, thre, dv, fe, ove;            //changed //"Flags de estado de la UART0"
wire [7:0]  uart_do;                            //changed //"Dato recibido por la UART0"
wire        uwrtx;                              //changed //"Strobe de escritura de TX_data en UART0"
wire        urd;                                //changed //"Strobe de lectura de RX_data en UART0 (limpia flags)"
wire        uwrbaud;                            //changed //"Strobe de escritura del divisor de baudios de UART0"

// UARTB0 (nueva UART con modo ráfaga)
wire        tend_b0, thre_b0, dv_b0, fe_b0, ove_b0;  //changed //"Flags de la UARTB0"
wire [7:0]  uartb0_do;                               //changed //"Dato recibido por la UARTB0"
wire        uwrtx_b0;                                //changed //"Strobe de escritura de TX_data en UARTB0"
wire        urd_b0;                                  //changed //"Strobe de lectura de RX_data en UARTB0"
wire        uwrbaud_b0;                              //changed //"Strobe de escritura de DIVIDER/MODE en UARTB0"
wire        txd_b0, rxd_b0;                          //changed //"Líneas serie de la UARTB0"

// En simulación aislada conectamos TXD_B0 con RXD_B0 (loopback interno)
// Esto permite comprobar que lo transmitido por uartb0 se recibe correctamente.
assign rxd_b0 = txd_b0;                              //changed //"Loopback UARTB0 para test en simulación"

//------------------------------------------------------------------
//  Mapeo de registros de la UART0 (igual que en el sistema original)
//------------------------------------------------------------------
parameter BAUDBITS = 12;                               //changed //"Número de bits del divisor de baudios"

assign uwrtx   = uartcs  & (~ca[2]) & mwe[0];          //changed //"Escritura en TX_data UART0 (offset 0x00)"
assign uwrbaud = uartcs  & ( ca[2]) & mwe[0] & mwe[1]; //changed //"Escritura en DIVIDER UART0 (offset 0x04)"
assign urd     = uartcs  & (~ca[2]) & (mwe==4'b0000);  //changed //"Lectura de RX_data UART0 (limpia DV/OVE)"

//------------------------------------------------------------------
//  Mapeo de registros de la UARTB0 (base 0xE000_0080)
//------------------------------------------------------------------
//  - 0xE000_0080 : TX_data / RX_data
//  - 0xE000_0084 : DIVIDER + MODE (bit 31)
assign uwrtx_b0   = uartb0cs & (~ca[2]) & mwe[0];          //changed //"Escritura en TX_data de UARTB0 (ráfaga o byte)"
assign urd_b0     = uartb0cs & (~ca[2]) & (mwe==4'b0000);  //changed //"Lectura de RX_data UARTB0 (limpia flags)"
assign uwrbaud_b0 = uartb0cs & ( ca[2]) & mwe[0] & mwe[1]; //changed //"Escritura en DIVIDER/MODE de UARTB0"

//------------------------------------------------------------------
//  Instancias de las dos UART
//------------------------------------------------------------------

// UART original (UART_CORE)                                          
UART_CORE #(.BAUDBITS(BAUDBITS)) uart0 (                   //changed //"Instancia de la UART original"
    .clk    (cclk      ),                                  //changed
    .txd    (txd       ),                                  //changed
    .rxd    (rxd       ),                                  //changed
    .d      (cdo[15:0] ),                                  //changed //"Solo usamos 16 bits de cdo para DIVIDER"
    .wrtx   (uwrtx     ),                                  //changed
    .wrbaud (uwrbaud   ),                                  //changed
    .rd     (urd       ),                                  //changed
    .q      (uart_do   ),                                  //changed
    .dv     (dv        ),                                  //changed
    .fe     (fe        ),                                  //changed
    .ove    (ove       ),                                  //changed
    .tend   (tend      ),                                  //changed
    .thre   (thre      )                                   //changed
);                                                         //changed

// Nueva UART con modo ráfaga (UARTB_CORE) Bit MODO en bit 31 de d
UARTB_CORE #(.BAUDBITS(BAUDBITS)) uartb0 (                 //changed //"Instancia de UARTB con soporte de ráfaga"
    .clk    (cclk      ),                                  //changed
    .txd    (txd_b0    ),                                  //changed
    .rxd    (rxd_b0    ),                                  //changed
    .d      (cdo       ),                                  //changed //"La lógica interna selecciona qué parte del bus usar"
    .wrtx   (uwrtx_b0  ),                                  //changed
    .wrbaud (uwrbaud_b0),                                  //changed
    .rd     (urd_b0    ),                                  //changed
    .q      (uartb0_do ),                                  //changed
    .dv     (dv_b0     ),                                  //changed
    .fe     (fe_b0     ),                                  //changed
    .ove    (ove_b0    ),                                  //changed
    .tend   (tend_b0   ),                                  //changed
    .thre   (thre_b0   )                                   //changed
);                                                         //changed



/////////////////////////////////////////////////////////
///////////////// Interrupt control /////////////////////
/////////////////////////////////////////////////////////

//////////////////////////////////////////
//    Interrupt control
//////////////////////////////////////////

//--------------------------------------------------------------
// Registro de habilitación de interrupciones (IRQEN)
//   bit 0 : UART0 RX (dv)
//   bit 1 : UART0 TX (thre)
//   bit 2 : UARTB0 RX (dv_b0)
//   bit 3 : UARTB0 TX (thre_b0)
//   bit 4 : reservado
//--------------------------------------------------------------
reg [4:0] irqen = 5'b0;                              //changed //"Registro de enable de interrupciones externas"

always @(posedge cclk or posedge reset) begin        //changed
    if (reset) begin                                 //changed
        irqen <= 5'b0;                               //changed //"Al hacer reset se deshabilitan todas las IRQ"
    end else if (irqcs & (~ca[4]) & mwe[0]) begin    //changed //"Escritura en 0xE000_00E0 actualiza IRQEN"
        irqen <= cdo[4:0];                           //changed
    end                                              //changed
end                                                  //changed

//--------------------------------------------------------------
// Vectores de interrupción
//   irqvect[0] : TRAP (ECALL/EBREAK)  -> 0xE00000F0
//   irqvect[1] : UART0 RX             -> 0xE00000F4
//   irqvect[2] : UART0 TX             -> 0xE00000F8
//   irqvect[3] : UARTB0 RX            -> 0xE00000FC
//   irqvect[4] : UARTB0 TX            -> 0xE00000E4
//--------------------------------------------------------------
reg [31:2] irqvect [0:4];                            //changed //"Cinco vectores de interrupción de 30 bits"

always @(posedge cclk) begin        //changed
	// Vectores 0..3 mapeados en 0xE00000F0-0xE00000FC      //changed
	if (irqcs & ca[4] & (mwe==4'b1111))     //changed
		irqvect[ca[3:2]] <= cdo[31:2];           //changed //"Dirección escrita según ca[3:2]"
	                                          //changed
	// Vector 4 mapeado en 0xE00000E4                         //changed
	if (irqcs & (~ca[4]) & (ca[3:2]==2'b01) & (mwe==4'b1111))                     //changed
		irqvect[4] <= cdo[31:2];                 //changed                                          //changed                                              //changed
end                                                  //changed

/*	
// Enabled IRQs
wire irqrx_group= ( irqen[0]&dv | irqen[1]&dv_b0 );// interrupciones lectura	
wire irqtx_group= ( irqen[3]&thre | irqen[4]&thre_b0);// interrupciones escritura	
wire [1:0] irqpen = {irqtx_group, irqrx_group};	// pending IRQs	
*/

//--------------------------------------------------------------
// Señales de petición de interrupción (pendientes)
//--------------------------------------------------------------
wire [4:0] irqpen;                                   //changed //"Flags de petición tras aplicar IRQEN"
assign irqpen[0] = irqen[0] & dv;                    //changed //"UART0 RX tiene datos pendientes"
assign irqpen[1] = irqen[1] & thre;                  //changed //"UART0 TX preparado para enviar"
assign irqpen[2] = irqen[2] & dv_b0;                 //changed //"UARTB0 RX tiene datos pendientes"
assign irqpen[3] = irqen[3] & thre_b0;               //changed //"UARTB0 TX preparado para enviar"
assign irqpen[4] = 1'b0;                             //changed //"Fuente reservada (no usada)"

/*

// Priority encoder
wire [1:0]vecn = trap      ? 2'b00 : (    // ECALL, EBREAK: highest priority
                 irqpen[0] ? 2'b01 : (    // UART RX
                 irqpen[1] ? 2'b10 : (  // UART TX
                 irqpen[2] ? 2'b11 :     // UART IGP0 //changed_2310 ¿¿¿¿¿¿???????????????
                              2'bxx )));
assign ivector = irqvect[vecn];
assign irq = (irqpen!=0)|trap;
*/
//--------------------------------------------------------------
// Priority encoder
//   Prioridad (de mayor a menor):
//      1) trap (software)
//      2) UART0 RX
//      3) UART0 TX
//      4) UARTB0 RX
//      5) UARTB0 TX
//--------------------------------------------------------------
reg [2:0] vecn;                                      //changed //"Índice del vector seleccionado"

always @* begin                                      //changed
    if (trap) begin                                  //changed
        vecn = 3'd0;                                 //changed //"trap tiene máxima prioridad"
    end else if (irqpen[0]) begin                    //changed
        vecn = 3'd1;                                 //changed
    end else if (irqpen[1]) begin                    //changed
        vecn = 3'd2;                                 //changed
    end else if (irqpen[2]) begin                    //changed
        vecn = 3'd3;                                 //changed
    end else if (irqpen[3]) begin                    //changed
        vecn = 3'd4;                                 //changed
    end else begin                                   //changed
        vecn = 3'd0;                                 //changed //"Si no hay IRQ externas, se vuelve al vector 0"
    end                                              //changed
end                                                  //changed

assign ivector = irqvect[vecn];                      //changed //"Dirección de servicio de interrupción hacia la CPU"
assign irq     = (irqpen != 5'b00000) | trap;        //changed //"Señal global de interrupción a la CPU"

/////////////////////////////////////////////////////////
///////////////////// OUTREG ////////////////////////////
/////////////////////////////////////////////////////////

reg [7:0] outreg;  // registro de salida general (8 bits)

always @(posedge cclk or posedge reset)
 if (reset) outreg <= 8'h00;
 else if (outcs & mwe[0]) outreg <= cdo[7:0];

/////////////////////////////////////////////////////////
/////////////////// RAM module //////////////////////////
/////////////////////////////////////////////////////////

endmodule

////////////

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
