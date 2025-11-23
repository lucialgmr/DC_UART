`timescale 1ns/10ps
`include "uart.v"

//-------------------------------------------------------------------
//-- Banco de pruebas 
//-------------------------------------------------------------------

module tb();

//-- Registos con señales de entrada
reg clk=0;
reg rxd=1;
reg wrtx=0;
reg wrbaud=0;
reg[15:0] d;
reg rd = 0;

UART_CORE myUART(
  .d(d),		 // Datos TX,BRG
  .wrtx(wrtx),    // Escritura en TX
  .wrbaud (wrbaud),	 // Escritura en BRG
  .rxd(rxd),     // Entrada RX
  .rd(rd),      // Lectura RX (borra DV)
  .clk(clk)
);

always #10 clk=~clk;	// #5 clk=~clk;		// periodo señal de reloj 10 ns

//-- Proceso al inicio
initial begin
	//-- Fichero donde almacenar los resultados
	$dumpfile("tb.vcd");
	$dumpvars(0, tb);
	# 8	 wrbaud = 1; d = 7; // d = 16;	// divido la frecuencia entre 17
	# 10 wrbaud = 0;
	#315 rxd=0;	// bit start		// los datos circulan a una velocidad algo mayor Tbit= 166 en vez de 170 ns
	#154 rxd=1; // D0=1  mucha sincronizacion, conmutan en cada bit
	#154 rxd=0; // D0=0
	#154 rxd=1; // D0=1
	#154 rxd=0; // D0=0
	#154 rxd=1; // D0=1
	#154 rxd=0; // D0=0
	#154 rxd=1; // D0=1
	#154 rxd=0; // D0=0
	#154 rxd=1; // stop
	#200 rd = 1;	// en teoría leo dato en bus cdi (system.v) y borro flags (dv)
	#10 rd = 0;
	#3  wrtx=1; d=16'h0041; // transmito A mayuscula
	#20 wrtx=0;
	#80 wrtx=1; d=16'h0043; // transmito C mayuscula (cambio paridad)
	#20 wrtx=0;

	#980 rxd=0;	// bit start
	#166 rxd=0; // D0=0
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=1; // stop
	rd = 1;
	#10 rd = 0;

	//# 319 $display("FIN de la simulacion");
	# 2000 $finish;
end



/*
//-- Proceso al inicio
initial begin
	//-- Fichero donde almacenar los resultados
	$dumpfile("tb.vcd");
	$dumpvars(0, tb);
	# 8	 wrbaud = 1; d = 17;		// divido la frecuencia entre 17
	# 10 wrbaud = 0;
	#315 rxd=0;	// bit start		// los datos circulan a una velocidad algo mayor Tbit= 166 en vez de 170 ns
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=1; // stop
	rd = 1;
	#10 rd = 0;
	#10 wrtx=1; d=16'h0041;
	#10 wrtx=0;

	#980 rxd=0;	// bit start
	#166 rxd=0; // D0=0
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=0; // D0=0
	#166 rxd=1; // D0=1
	#166 rxd=0; // D0=0
	#166 rxd=1; // stop
	rd = 1;
	#10 rd = 0;

	//# 319 $display("FIN de la simulacion");
	# 650 $finish;
end
*/
endmodule


