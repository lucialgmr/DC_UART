//----------------------------------------------------------------------
// Testbench para el Sistema con UART B
// (Prueba de Loopback para UARTB_CORE)
//----------------------------------------------------------------------
`timescale 1ns/1ns

module tb_uartb;

    // 1. Señales del sistema
    reg clk;
    reg reset;
    
    // Señales UART0 (no usadas en esta prueba, pero necesarias para el puerto)
    wire txd_0;
    reg rxd_0;
    
    // (modificado1511) Señales de la nueva UARTB
    wire txd_b0;
    wire rxd_b0; // Debe ser wire para el loopback en el testbench
    
    // Señales de salida del sistema
    wire [31:0] salida;
    wire sck, mosi, miso, fssb;

    // 2. Definición del periodo de reloj
    parameter CLK_PERIOD = 20; // 50 MHz (20ns) o el que uses en tu proyecto

    // 3. Generación de reloj (mitad de periodo para flanco)
    always
        #(CLK_PERIOD/2) clk = ~clk;

    // 4. Instanciación del Sistema (SYSTEM)
    // Asumo que el módulo SYSTEM necesita los puertos originales (UART0)
    // y los puertos de la nueva UARTB si los hubieras expuesto.
    // Como en system.v definimos txd_b0 y rxd_b0 internamente,
    // usamos la conexión del loopback aquí.
    
    SYSTEM dut (
        .clk(clk),
        .reset(reset),
        
        // UART0 (Sin conexión activa)
        .rxd(rxd_0),
        .txd(txd_0),
        
        // Salidas/Periféricos
        .salida(salida),
        .sck(sck),
        .mosi(mosi),
        .miso(1'b0), // Miso a 0
        .fssb(fssb)
    );

    // 5. (modificado1511) Conexión Loopback para UARTB
    // Cortocircuitar la salida serie txd_b0 con la entrada rxd_b0.
    // ESTA CONEXIÓN FUE DEFINIDA EN system.v como: assign rxd_b0 = txd_b0;
    // Si la definiste en el system.v, aquí solo necesitas las wires de conexión.
    // Si necesitas la conexión aquí, descomenta la línea de assign:
    // assign rxd_b0 = txd_b0;
    
    // Dado que txd_b0 y rxd_b0 son señales internas del SYSTEM,
    // debes incluirlas en el dump, y la conexión ya está en system.v.

    // 6. Tarea de DUMP y Simulación
    initial begin
        // Inicialización de señales
        clk = 1'b0;
        reset = 1'b1; // Reset activo al inicio

        // Dump para visualización
        $dumpfile("tb_uartb.vcd");
        // (modificado1511) Visualización de todos los registros internos de la CPU (dut.cpu)
        $dumpvars(0, dut.cpu);
        // (modificado1511) Visualización de vectores IRQ y registros de la nueva UART
        $dumpvars(0, dut.irqvect, dut.uartb0);
        // (opcional: señales importantes del bus)
        $dumpvars(0, dut.ca, dut.cdo);
        
        // 7. Secuencia de Simulación
        // 7.1. Aplicar Reset
        @(posedge clk) #1;
        @(posedge clk) reset = 1'b0; // Desactivar reset

        // 7.2. Esperar el tiempo necesario para la prueba del start.S
        // El programa start.S ejecuta transmisiones, espera suficiente tiempo
        // para que se completen las ráfagas (4 bytes * 9 bits/byte * DIVIDER).
        
        // Usaremos 500,000 ciclos de reloj para la simulación
        repeat (500000) @(posedge clk);
        
        // 7.3. Finalizar
        $finish;
    end

endmodule
