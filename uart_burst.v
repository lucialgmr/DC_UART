//---------------------------------------------
//        Core de UART
//    - Doble función de transmisor y receptor
//  - MODOS NORMAL y RÁFAGA
//---------------------------------------------

module UARTB_CORE(
  output txd,    // Salida TX
  output tend,     // Flag TX completa
  output thre,   // Flag Buffer TX vacío
  input [31:0]d, // Datos TX (32 bits), BRG (parte baja)
  input wrtx,    // Escritura en TBR
  input wrbaud,     // Escritura en BRG y MODE
  output [7:0]q, // Datos RX
  output dv,     // Flag dato RX válido
  output fe,     // Flag Framing Error
  output ove,    // Flag Overrun
  input rxd,     // Entrada RX
  input rd,      // Lectura RX (borra DV)
  input clk
);

parameter BAUDBITS=9;

// (modificado1511) Nuevos registros para la implementación de modos
reg [31:0]tbr;      // Transmitter Buffer Register (32 bits)
reg mode;           // 1: Ráfaga, 0: Normal (configurado con wrbaud, bit 31)
reg moden;          // Registro del modo para la próxima carga a THR (registrado con wrtx)
reg [1:0] cntbyte;  // Contador de bytes para el modo ráfaga (0 a 3)
reg data_word_pending = 1'b0; // Señal de palabra disponible en tbr
reg thr_just_loaded = 1'b0; // Señal para resetear divtx y empezar la transmisión

//---------------------------------------------------------
// Bloque de Escritura: TBR, BRG y MODE
//---------------------------------------------------------

// (modificado1511) BAUD Rate Generation y Registro MODE
reg [BAUDBITS-1:0]divider=0;
always @(posedge clk) begin
    if (wrbaud) begin
        divider<=d[BAUDBITS-1:0]; // BRG en los bits bajos de D
        mode<=d[31];              // Bit MODO en bit 31 de D
    end
end

// (modificado1511) Registro TBR y Registro MODEN
always @(posedge clk) begin
    if (wrtx) begin
        tbr<=d;           // La CPU escribe 32 bits en TBR (Dirección Base)
        moden<=mode;      // Se registra el modo actual para la futura transmisión
        data_word_pending <= 1'b1; // Nueva palabra para transmitir
        cntbyte <= 2'b00; // Resetear el contador de byte para empezar desde LSB (Byte 0)
    end
end

//---------------------------------------------------------
//  Transmisor (Adaptado)
//---------------------------------------------------------
reg [7:0]thr;           // Buffer TX (8 bits)
reg thre=1;                // Estado THR 1: vacío, 0: con dato
reg [8:0]shtx=9'h1FF;    // Reg. desplazamiento de 9 bits
reg [3:0]cntbit;        // Contador de bits transmitidos
reg rdy=1;                // Estado reg. despl. (1==idle)

// Divisor de TX (modificado1511) Ahora depende de la carga de THR
reg [BAUDBITS-1:0] divtx=0;
wire clko;                // pulsos de 1 ciclo de salida
assign clko = (divtx==0);
always @ (posedge clk)
    divtx <= thr_just_loaded ? 0 : (clko ? divider: divtx-1); // Resetea divtx cuando THR es cargado

// (modificado1511) Lógica de extracción de byte de TBR a THR
wire next_byte_request;
assign next_byte_request = thre & rdy; // THR vacío Y Shift Register idle

always @(posedge clk) begin
    // Resetear flag de carga al inicio del ciclo
    thr_just_loaded <= 1'b0;

    if (next_byte_request) begin // Si la UART está lista para el siguiente byte
        if (data_word_pending) begin // Y hay una palabra pendiente en TBR
            if (moden == 1'b0) begin // MODO NORMAL: Envío de 1 byte
`ifdef SIMULATION
                $write ("%c",tbr&255); // Solo muestra el LSB
                $fflush ( );
`endif
                thr <= tbr[7:0];
                thre <= 1'b0; // THR ocupado
                thr_just_loaded <= 1'b1; // Activar pulso para divtx
                data_word_pending <= 1'b0; // Palabra enviada (solo 1 byte en modo normal)
            end else begin // MODO RÁFAGA: Envío de 4 bytes secuenciales
                // Selecciona el byte a transmitir
                case (cntbyte)
                    2'b00: thr <= tbr[7:0];   // Byte 0
                    2'b01: thr <= tbr[15:8];  // Byte 1
                    2'b10: thr <= tbr[23:16]; // Byte 2
                    2'b11: thr <= tbr[31:24]; // Byte 3
                    default: thr <= 8'hXX; // No debería pasar
                endcase
                
                thre <= 1'b0; // THR ocupado
                thr_just_loaded <= 1'b1; // Activar pulso para divtx
                
                // Actualiza el contador y el flag de palabra pendiente
                if (cntbyte == 2'b11) begin // Final de la ráfaga (byte 3)
                    data_word_pending <= 1'b0; // Palabra completa enviada
                    cntbyte <= 2'b00; // Resetear
                end else begin
                    cntbyte <= cntbyte + 1; // Avanzar al siguiente byte
                end
            end
        end
    end

    // (modificado1511) Lógica de carga de registro de desplazamiento (Shift Register)
    // El cargado ocurre si THR acaba de cargarse (thr_just_loaded=1)
    if(thr_just_loaded) begin
        rdy<=1'b0;
        thre<=1'b1; // THR se vacía inmediatamente al cargar el Shift Register
        shtx<={thr[7:0],1'b0};  // Incluido bit de START
        cntbit<=4'b0000;
    end
    
    // Lógica de desplazamiento y conteo (sin cambios)
    if (clko) begin
        if(~rdy) begin             // Desplazamiento de bits
            shtx<={1'b1,shtx[8:1]};
            cntbit<=cntbit+1;
            if (cntbit[3]&cntbit[0]) rdy<=1'b1; // 9 bits: terminado
        end
    end
end

assign txd = shtx[0];
assign tend = thre&rdy; // Flag de TX completa (THR vacío Y Shift Register idle)

//---------------------------------------------------------
//  Receptor (Sin Modificar)
//---------------------------------------------------------

/// Sincronismo de reloj
reg [1:0]rrxd=0; // RXD registrada dos veces
wire resinc;
wire falling;          // activa si flanco de bajada en RXD (para start)
always @(posedge clk) rrxd<={rrxd[0],rxd};
assign resinc = rrxd[0]^rrxd[1];
assign falling = (~rrxd[0])&rrxd[1];

/// Divisor
// Genera un pulso en mitad de la cuenta (centro de bit)
// se reinicia con resinc
reg [BAUDBITS-1:0] divrx=0;
wire shift;        // Pulso de 1 ciclo de salida
wire clki0;        // recarga de contador
assign shift = (divrx=={1'b0,divider[BAUDBITS-1:1]});
assign clki0= (divrx==0);
always @ (posedge clk) divrx <= (resinc|clki0) ? divider: divrx-1;

reg dv=0;               // Dato válido si 1
reg ove=0;
reg [8:0]shrx;          // Reg. desplazamiento entrada (9 bits para stop)
reg [7:0]rbr;           // Buffer RX
reg stopb;
reg [3:0]cbrx=4'b1111;  // Contador de bits / estado (1111== idle)
wire rxst;
assign rxst=(cbrx==4'b1111);
reg rxst0;

always @(posedge clk)
begin
    rxst0<=rxst;
    if (rxst & falling) cbrx<=4'h9; // START: 9 bits a recibir
    if (shift & (~rxst)) begin       // Desplazando y contando bits
        shrx<= {rrxd[0],shrx[8:1]};
        cbrx<=cbrx-1;
    end
    if (rxst & (~rxst0)) begin   // Final de cuenta
        {stopb,rbr}<=shrx;      // Guardando dato y bit STOP
        dv<=1;                  // Dato válido
        ove<=dv;                // Overrun si ya hay dato válido
    end

    if (rd) begin   // Lectura: Borra flags
        dv<=0;
        ove<=0;
    end
end

assign fe=~stopb;   // el Flag FE es el bit de STOP invertido
assign q = rbr;

endmodule
