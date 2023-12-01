//本设计由外部输入8位有效数据，然后以串行的方式输出该字节对应的数据帧，共11位数据，还包含起始位、校验位、停止位。通信波特率为115200，开发板系统时钟为100Mhz，即发送一位数据需要100000000/115200 = 868个系统时钟。

module uart_tx(
    input wire  sys_clk,
    input wire  sys_rst_n,
    input wire[7:0]  td_data,   //the parall data to send in need
    input wire  ready_flag,

    output wire out_data    // the ready to send by bit
);

    //parameter
    parameter baud_cnt = 868;   // calculate from above desciption

 // reg define
    reg [10:0]  tx_data; //完整的一帧数据，共11位 = 8b data + 1b st + 1b end + 1b chk
    reg [3:0]   bit_cnt; //对发送的位数计数，计数范围0-10 + 1
    reg [9:0]   clk_cnt; //对发送的位数计数，计数范围0-10 + 1
    reg         work_flag; //发送当前帧数据时，不再接收外部传入的8位数据,1为有效
    reg [7:0]   data_reg; //当前需发送的有效数据 

    // wire define
    wire        parity; //校验位

    //外部输入有效且当前无发送任务时，寄存需要输出的8位数据
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            data_reg <= 0;
        else if(ready_flag && ~work_flag) //外部输入有效且当前无任务
            data_reg <= td_data;
        else if(~ready_flag && ~work_flag) 
            data_reg <= 0;
        else if(work_flag)
            data_reg <= data_reg;
    end

    // 发送工作使能信号
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            work_flag <= 0;
        else if(ready_flag && ~work_flag) //外部输入有效且当前无任务
            work_flag <= 1;
        else if(clk_cnt == baud_cnt-1 && bit_cnt == 10)
            work_flag <= 0;
    end

    //得到有效数据对应的校验位
    parity_gen #(
    .DATA_WIDTH       ( 8 ),
    .PARITY_TYPE      ( 1 ))
     u_parity_gen (
    .sys_clk                 ( sys_clk      ),
    .sys_rst_n               ( sys_rst_n    ),
    .data_in                 ( data_reg     ),
    .data_valid              ( work_flag    ),

    .parity                  ( parity       )
    );

    //对系统时钟计数，每868个时钟
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            clk_cnt <= 0;
        else if(clk_cnt == baud_cnt-1 && work_flag)
            clk_cnt <= 0;
        else if(work_flag)
            clk_cnt <= clk_cnt + 1;
    end

    //确定发送第几位数据（总共11位，0-10)
    always @(posedge sys_clk or negedge sys_rst_n ) begin
        if(!sys_rst_n)
            bit_cnt <= 0;
        else if(clk_cnt==baud_cnt-1 && work_flag)begin
            if(bit_cnt == 10)   //11b data
                bit_cnt <= 0;
            else
                bit_cnt <= bit_cnt + 1;
        end
    end

    //完整的要发送的11位数据
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            tx_data <= 0;
        else if(work_flag)
            tx_data <= {1'b1, parity, data_reg, 1'b0};
        else
            tx_data <= 0;
    end

    //在发送数据时每一位
    assign out_data = work_flag ? tx_data[bit_cnt]:1;

endmodule
