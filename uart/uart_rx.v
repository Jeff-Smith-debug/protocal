//本模块由外部串行输入11位数据，空闲状态输入为高电平，通过下降沿输入起始位，依次输入8位有效数据、校验位、停止位。通信波特率为115200，开发板系统时钟为100Mhz，即每隔100000000/115200 = 868个系统时钟输入一位数据。通过移位的方法得到11位数据后，取其中的8位有效数据，计算出其校验位并与接收到的校验位进行比较，如果与接收到的校验位相同，则收到数据无误（概率上），输出8位有效数据及数据有效标志，否则，数据有效标志保持为0。由于uart收到的数据由其他设备传送，为跨时钟域传输（由上位机慢速时钟域到FPGA快速时钟域），因此存在数据传输亚稳态问题，因此输入的数据需要打两拍。另一个需要注意的点为要对起始位下降沿检测，作为数据帧开始传输的标志。

module uart_rx (
    input       sys_clk,
    input       sys_rst_n,
    input       data_in,    //serial data_in

    output  reg [7:0] valid_data,
    output  reg       valid_flag
);

    //parameter define
    parameter baud_cnt = 868;
    parameter rece_data_width = 8 + 3;

    //reg define
    reg     data_in_reg1;
    reg     data_in_reg2;       //将输入数据打两拍
    reg     data_in_reg3;       //再寄存一位，用于起始位下降沿检测，共打了3拍

    reg     rece_flag;          //检测到下降沿后，开始数据帧的接收
    reg [9:0]   clk_cnt;    //每经过868个系统时钟，接收一次串口数据
    reg [3:0]   rece_bit_cnt;//对收到的帧数据位数计数，0-10
    reg [10:0]  rece_data;   //收到的11位数据
    reg     rece_done_flag;     //接收完一帧数据标志

    //wire define
    wire parity_cal;   //对接收到的数据判断得到的校验位

    //输入数据,delay 3 DFF;
    always @(posedge sys_clk or negedge sys_rst_n ) begin
        if(!sys_rst_n)begin
            data_in_reg1 <= 1;
            data_in_reg2 <= 1;
            data_in_reg3 <= 1;
        end
        else begin
            data_in_reg1 <= data_in;
            data_in_reg2 <= data_in_reg1;
            data_in_reg3 <= data_in_reg2;
        end
    end

    // 检测下降沿
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            rece_flag <= 0;
        else if(!data_in_reg2 && data_in_reg3 && !rece_flag)
            rece_flag <= 1;
        //已经收到了11位数据，结束本帧数据的传输
        else if(rece_flag && (rece_bit_cnt == rece_data_width - 1) && (clk_cnt == baud_cnt -1))
            rece_flag <= 0;
    end

    //对系统时钟计数，每868个时钟
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            clk_cnt <= 0;
        else if(rece_flag)begin
            if(clk_cnt == baud_cnt - 1)
                clk_cnt <= 0;
            else
                clk_cnt <= clk_cnt + 1; 
        end    
    end

    //对收到的每帧数据位数计数，0-10
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            rece_bit_cnt <= 0;
        else if(clk_cnt == baud_cnt - 1 && rece_flag)
            if(rece_bit_cnt == rece_data_width - 1)
                rece_bit_cnt <= 0;
            else
                rece_bit_cnt <= rece_bit_cnt + 1;
    end

    //在baud_cnt一半的系统时钟时取数据
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            rece_data <= 11'b11111111111; 
        else if(clk_cnt == baud_cnt/2)
            rece_data <= {data_in_reg3, rece_data[10:1]};   //shifet to update
    end

    //接收完数据给一个flag，只保持一个时钟周期
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            rece_done_flag <= 0;
        else if(rece_flag && (rece_bit_cnt == rece_data_width - 1) && (clk_cnt == baud_cnt -1))
            rece_done_flag <= 1;
        else //只保持一个时钟，就恢复为0
            rece_done_flag <= 0;
    end

    //取得本帧数据的校验位
    parity_gen #(
    .DATA_WIDTH       ( 8 ),
    .PARITY_TYPE      ( 1 ))
     u2_parity_gen (
    .sys_clk                 ( sys_clk          ),
    .sys_rst_n               ( sys_rst_n        ),
    .data_in                 ( rece_data[8:1]   ),
    .data_valid              ( rece_done_flag   ),
    .parity                  ( parity_cal       )
    );

    //如果计算的校验位与接收的数据校验位相同，valid_flag一个高脉冲
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            valid_flag <= 0;
        else if(rece_done_flag)begin
            if(parity_cal == rece_data[9])
                valid_flag <= 1;
            end
        else
                valid_flag <= 0;
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if(!sys_rst_n)
            valid_data <= 0;
        else if(valid_flag)
            valid_data <= rece_data[8:1];
        else
            valid_data <= valid_data;
    end

endmodule
