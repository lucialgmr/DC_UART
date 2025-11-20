`timescale 1ns / 1ps


module UARTB_CORE_tb;

    // ------------------------------------------------------------------
    // 1. Señales del Módulo a Probar (DUT)
    // ------------------------------------------------------------------
    reg clk;
    reg rxd;
    reg rd;
    reg wrtx;
    reg wrbaud;
    reg [31:0] d;

    wire txd;
    wire tend;
    wire thre;
    wire [7:0] q;
    wire dv;
    wire fe;
    wire ove;

    // ------------------------------------------------------------------
    // 2. Conexión del DUT
    // ------------------------------------------------------------------
    UARTB_CORE DUT (
        .txd(txd),
        .tend(tend),
        .thre(thre),
        .d(d),
        .wrtx(wrtx),
        .wrbaud(wrbaud),
        .q(q),
        .dv(dv),
        .fe(fe),
        .ove(ove),
        .rxd(rxd),
        .rd(rd),
        .clk(clk)
    );

    // Cortocircuitar txd con rxd
    assign rxd = txd; //

    // ------------------------------------------------------------------
    // 3. Generación del Reloj (50% Duty Cycle)
    // ------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #10 clk = ~clk; // Reloj de 50 MHz (20ns ciclo)
    end

    // ------------------------------------------------------------------
    // 4. Secuencia de Estímulos
    // ------------------------------------------------------------------
    initial begin
        // Valores Iniciales de Control
        rd = 0;
        wrtx = 0;
        wrbaud = 0;
        d = 0;

        $display("--- Inicio de Simulación ---");

        // -------------------------------------------------------
        // FASE 1: Configuración Inicial (MODO NORMAL)
        // -------------------------------------------------------
        // Configurar DIVIDER = 7 (BRG factor 8) y MODE = 0 (Normal)
        // Suponemos que el bit MODO es el bit 31 de D.
        #100;
        $display("1. Configurando DIVIDER=7 y MODE=NORMAL (0).");
        d = {1'b0, 22'h0, 9'd7}; // Bit 31 = 0 (Normal), Bits [8:0] = 7 (Divider)
        wrbaud = 1;
        #20;
        wrbaud = 0;
        d = 0;
        
        // -------------------------------------------------------
        // FASE 2: Transmisión en MODO NORMAL (4 bytes, uno por store)
        // -------------------------------------------------------
        // En modo Normal, la CPU envía un byte en D[7:0] por cada store.
        #100;
        $display("2. Enviando datos en MODO NORMAL (0xAA, 0x55, 0x0F, 0xF0).");

        // Dato 1: 0xAA
        @(posedge clk) d = 8'hAA; wrtx = 1;
        @(posedge clk) wrtx = 0; d = 0;
        // Esperar a que el transmisor esté libre para el siguiente (thre=1)
        wait(thre) @(posedge clk);
        
        // Dato 2: 0x55
        @(posedge clk) d = 8'h55; wrtx = 1;
        @(posedge clk) wrtx = 0; d = 0;
        wait(thre) @(posedge clk);

        // Dato 3: 0x0F (Interrumpir aquí)
        @(posedge clk) d = 8'h0F; wrtx = 1;
        @(posedge clk) wrtx = 0; d = 0;

        // -------------------------------------------------------
        // FASE 3: Conmutación a MODO RÁFAGA e inicio de transmisión BURST
        // -------------------------------------------------------
        // Conmutar a MODO RÁFAGA (mode=1)
        #100; // Un pequeño retraso para ver el inicio de 0x0F
        $display("3. Conmutando a MODO RÁFAGA (1) y enviando 32 bits.");
        
        // Suponemos que la CPU cambia el modo en Dirección Base+4:
        d = {1'b1, 22'h0, 9'd7}; // Bit 31 = 1 (Ráfaga), Divider = 7 (sin cambiar)
        wrbaud = 1;
        #20;
        wrbaud = 0;
        d = 0;

        // Escribir 32 bits en TBR (Dirección Base)
        @(posedge clk) d = 32'h11223344; // 11=D[31:24], 22=D[23:16], 33=D[15:8], 44=D[7:0]
        wrtx = 1;
        @(posedge clk) wrtx = 0; d = 0;

        // Esperar la transmisión de los 4 bytes de la ráfaga (esto tomará tiempo)
        // Simplemente esperamos un tiempo prudencial (ej. 4 veces la transmisión normal)
        #5000;

        // -------------------------------------------------------
        // FASE 4: Vuelve a MODO NORMAL
        // -------------------------------------------------------
        #100;
        $display("4. Volviendo a MODO NORMAL (0) y enviando dato final.");
        
        // Volver a MODO NORMAL
        d = {1'b0, 22'h0, 9'd7}; // Bit 31 = 0 (Normal), Divider = 7
        wrbaud = 1;
        #20;
        wrbaud = 0;
        d = 0;

        // Dato final: 0xDE
        @(posedge clk) d = 8'hDE; wrtx = 1;
        @(posedge clk) wrtx = 0; d = 0;
        wait(thre) @(posedge clk);

        #500;
        $display("--- Fin de Simulación ---");
        $finish;
    end

    // Tarea para leer el registro del receptor y limpiar el flag dv
    always @(posedge dv) begin
        if (dv) begin
            $display("@%0t: RX Dato Válido: q=0x%h. Limpiando DV...", $time, DUT.rbr);
            @(posedge clk) rd = 1;
            @(posedge clk) rd = 0;
        end
    end

endmodule
