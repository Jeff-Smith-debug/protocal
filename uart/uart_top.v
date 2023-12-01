//本模块用于与上位机串口助手软件通信，将收到的上位机数据再通过uart传回去
module uart_top (
    input   sys_clk,
    input   sys_rst_n,
    input   data_rx,
    output  data_tx
);

    // parameter define
    parameter  baud_cnt = 868;
    parameter  data_width = 8 + 3;

    //reg define
    // 由于接收模块的数据有效标志只维持了一个时钟，因此将该标志延迟一个时钟给发送模块
    reg tran_data_ready; 

    //wire define
    wire [7:0] valid_rece_data;
    wire       valid_rece_flag;

    uart_rx #(
    .baud_cnt        ( baud_cnt   ),
    .rece_data_width ( data_width ))
    u_uart_rx (
    .sys_clk                 ( sys_clk           ),
    .sys_rst_n               ( sys_rst_n         ),
    .data_in                 ( data_rx           ),

    .valid_data              ( valid_rece_data   ),
    .valid_flag              ( valid_rece_flag   )
);

    always @(posedge sys_clk or negedge sys_rst_n ) begin
        if(!sys_rst_n)
            tran_data_ready <= 0;
        else if(valid_rece_flag)
            tran_data_ready <= 1;
        else
            tran_data_ready <= 0;
    end

    uart_tx #(
        .baud_cnt        ( baud_cnt ),
        .tran_data_width (data_width))
     u_uart_tx (
        .sys_clk                 ( sys_clk           ),
        .sys_rst_n               ( sys_rst_n         ),
        .td_data                 ( valid_rece_data   ),
        .ready_flag              ( tran_data_ready   ),

        .out_data                ( data_tx           )
    );

endmodule

