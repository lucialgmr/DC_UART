`timescale 1ns/1ps

`define SIMULATION

module tb;

    // Señales de reloj y reset global
    reg clk   = 1'b0;
    reg reset = 1'b1;

    // Señales de la UART "clásica" del sistema (no la nueva uartb0)
    wire txd;
    wire rxd;

    // SPI y salida general (no los usamos en la prueba)
    wire [31:0] salida;
    wire sck;
    wire mosi;
    reg  miso = 1'b1;   // MISO en '1' (línea en reposo)
    wire fssb;

    //--------------------------------------------------------------------------
    // Generación de reloj
    //--------------------------------------------------------------------------
    // El sistema asume clk = 25 MHz -> periodo 40 ns (20 ns high, 20 ns low)
    localparam CLK_PERIOD = 40;

    always #(CLK_PERIOD/2) clk = ~clk;

    //--------------------------------------------------------------------------
    // Instanciación del sistema completo
    //--------------------------------------------------------------------------
    // OJO: En system.v ya existe la UARTB_CORE (uartb0) con loopback interno:
    //   wire txd_b0, rxd_b0;
    //   assign rxd_b0 = txd_b0;
    // Por tanto, el cortocircuito TXD_B0-RXD_B0 ya está hecho dentro del DUT.

    SYSTEM dut (
        .clk   (clk),
        .reset (reset),

        // UART "principal"
        .rxd   (rxd),
        .txd   (txd),

        .salida(salida),

        // SPI
        .sck   (sck),
        .mosi  (mosi),
        .miso  (miso),
        .fssb  (fssb)
    );

    // Para dejar la UART0 en reposo, ponemos RXD a '1' (idle)
    assign rxd = 1'b1;

    //--------------------------------------------------------------------------
    // Inicialización: reset, dumps y tiempo de simulación
    //--------------------------------------------------------------------------

    initial begin
        // Fichero de ondas
        $dumpfile("tb.vcd");
        // Volcado de todo el testbench y del sistema (incluyendo CPU y UARTB)
        $dumpvars(0, tb);
        $dumpvars(0, dut);
        $dumpvars(0, dut.uartb0);   // Registrar internos de UARTB_CORE (rbr, dv, etc)
        // Si conoces el nombre del módulo de CPU (por ejemplo "cpu" dentro de SYSTEM),
        // puedes activar también:
        // $dumpvars(0, dut.cpu);

        // Reset activo al principio
        reset = 1'b1;
        #(10*CLK_PERIOD);   // Mantenemos reset unos ciclos
        reset = 1'b0;

        // Tiempo máximo de simulación: p.ej. 10 ms
        #(10_000_000);      // 10 ms con timescale 1ns
        $display("Fin de simulación por timeout.");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Monitor opcional del receptor de la nueva UART (uartb0)
    //--------------------------------------------------------------------------
    // En UARTB_CORE el registro de recepción se llama rbr y la flag dv.
    // Los podemos observar por jerarquía (se verán bien en la traza).

    // Muestra cada vez que llega un carácter válido a la UARTB0
    always @(posedge dut.uartb0.dv) begin
        $display("[%0t ns] UARTB0 RX: rbr = 0x%02h (%c)",
                 $time, dut.uartb0.rbr,
                 (dut.uartb0.rbr >= 8'h20 && dut.uartb0.rbr <= 8'h7E) ?
                    dut.uartb0.rbr : 8'h2E); // imprime '.' si no es imprimible
    end

    // También podemos vigilar el flag THRE de UARTB0 para ver las interrupciones TX
    always @(posedge clk) begin
        if (dut.thre_b0)
            $display("[%0t ns] UARTB0 THRE=1 (TX holding register vacío)", $time);
    end

endmodule
