//ref link:[1] https://github.com/freecores/jtag/blob/master/tap/rtl/verilog/tap_top.v
//          [2]https://www.fpga4fun.com/JTAG2.html 
//          [3]https://www.xjtag.com/about-jtag/jtag-a-technical-overview/ 
//final from: www.opencores.com
//Jtag: TDI,TDO,TMS and TCK;
//What is important is that TAP controller state machine
//Shift-DR and shift-IR are used in combination with the TDI and TDO lines;

//IR--Instruction Register;  DR:Data Register;
//=================================================

//DR--Data Register;each IR value selects a different DR;
