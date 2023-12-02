@[TOC](SPI Verilog)
Ref: 1.https://juejin.cn/post/7218417913095323707
     2.https://www.cnblogs.com/ransn/p/11452197.html 
在芯片中只占用四根管脚用来控制及数据传输，广泛用于EEPROM、Flash、RTC（实时时钟）、ADC（数模转换器）、DSP（数字信号处理器）以及数字信号解码器上

SPI总线传输只需要4根线就能完成，这四根线的作用分别如下：
　　　　SCK(Serial Clock)：SCK是串行时钟线，作用是Master向Slave传输时钟信号，控制数据交换的时机和速率；
　　　　MOSI(Master Out Slave in)：在SPI Master上也被称为Tx-channel，作用是SPI主机给SPI从机发送数据；
　　　　CS/SS(Chip Select/Slave Select)：作用是SPI Master选择与哪一个SPI Slave通信，低电平表示从机被选中(低电平有效)；
　　　　MISO(Master In Slave Out)：在SPI Master上也被称为Rx-channel，作用是SPI主机接收SPI从机传输过来的数据；
