module iic_recv
(
    input                I_clk           , // 系统50MHz时钟
    input                I_rst_n         , // 系统全局复位
    input                I_iic_recv_en   , // IIC发送使能位
    
    input        [6:0]   I_dev_addr      , // IIC设备的物理地址
    input        [7:0]   I_word_addr     , // IIC设备的字地址，即我们想操作的IIC的内部地址
    output  reg  [7:0]   O_read_data     , // 从IIC设备的字地址读出来的数据   
    output  reg          O_done_flag     , // 读或写IIC设备结束标志位
    
    // 标准的IIC设备总线
    output               O_scl           , // IIC总线的串行时钟线
    inout                IO_sda            // IIC总线的双向数据线
);          

parameter   C_DIV_SELECT        =   10'd500 ; // 分频系数选择

parameter   C_DIV_SELECT0       =   (C_DIV_SELECT >> 2)  -  1           , // 用来产生IIC总线SCL低电平最中间的标志位
            C_DIV_SELECT1       =   (C_DIV_SELECT >> 1)  -  1           , // 用来产生IIC串行时钟线
            C_DIV_SELECT2       =   (C_DIV_SELECT0 + C_DIV_SELECT1) + 1 , // 用来产生IIC总线SCL高电平最中间的标志位
            C_DIV_SELECT3       =   (C_DIV_SELECT >> 1) + 1             ; // 用来产生IIC总线SCL下降沿标志位
 

reg     [9:0]   R_scl_cnt       ; // 用来产生IIC总线SCL时钟线的计数器   
reg             R_scl_en        ; // IIC总线SCL时钟线使能信号
reg     [3:0]   R_state         ; 
reg             R_sda_mode      ; // 设置SDA模式，1位输出，0为输入
reg             R_sda_reg       ; // SDA寄存器
reg     [7:0]   R_load_data     ; // 发送/接收过程中加载的数据，比如设备物理地址，字地址和数据等
reg     [3:0]   R_bit_cnt       ; // 发送字节状态中bit个数计数
reg             R_ack_flag      ; // 应答标志
reg     [3:0]   R_jump_state    ; // 跳转状态，传输一个字节成功并应答以后通过这个变量跳转到导入下一个数据的状态
reg     [7:0]   R_read_data_reg ;

wire            W_scl_low_mid   ; // SCL的低电平中间标志位
wire            W_scl_high_mid  ; // SCL的高电平中间标志位

assign IO_sda  =  (R_sda_mode == 1'b1) ? R_sda_reg : 1'bz ;

always @(posedge I_clk or negedge I_rst_n)
begin
    if(!I_rst_n)
        R_scl_cnt   <=  10'd0 ; 
    else if(R_scl_en)   
        begin
            if(R_scl_cnt == C_DIV_SELECT - 1'b1)
                R_scl_cnt <= 10'd0 ;
            else
                R_scl_cnt <= R_scl_cnt + 1'b1 ;     
        end
    else
        R_scl_cnt     <= 10'd0 ;
end

assign O_scl           = (R_scl_cnt <= C_DIV_SELECT1) ? 1'b1 : 1'b0 ; // 产生串行时钟信号O_scl
assign W_scl_low_mid  = (R_scl_cnt == C_DIV_SELECT2) ? 1'b1 : 1'b0 ; // 产生scl低电平正中间标志位
assign W_scl_high_mid = (R_scl_cnt == C_DIV_SELECT0) ? 1'b1 : 1'b0 ; // 产生scl高电平正中间标志位
assign W_scl_neg       = (R_scl_cnt == C_DIV_SELECT3) ? 1'b1 : 1'b0 ; // 产生scl下降沿标志位

always @(posedge I_clk or negedge I_rst_n)
begin
    if(!I_rst_n)
        begin
            R_state         <=  4'd0 ;
            R_sda_mode      <=  1'b1 ;
            R_sda_reg       <=  1'b1 ;
            R_bit_cnt       <=  4'd0 ;
            O_done_flag     <=  1'b0 ;
            R_jump_state    <=  4'd0 ;
            R_read_data_reg <=  8'd0 ;
            R_ack_flag        <=    1'b0 ;
            O_read_data        <=    8'd0 ;
        end
    else if(I_iic_recv_en) // 往IIC设备发送数据
        begin
            case(R_state)
                4'd0    :   // 空闲状态，用来初始化相关所有信号
                    begin
                        R_sda_mode      <=  1'b1 ; // 设置SDA为输出
                        R_sda_reg       <=  1'b1 ; // 设置SDA为高电平
                        R_scl_en        <=  1'b0 ; // 关闭SCL时钟线
                        R_state         <=  4'd1 ; // 下一个状态是加载设备物理地址状态
                        R_bit_cnt       <=  4'd0 ;
                        O_done_flag     <=  1'b0 ;
                        R_jump_state    <=  5'd0 ;
                        R_read_data_reg <=  8'd0 ;
                    end
                4'd1    :   // 加载IIC设备物理地址 
                    begin
                        R_load_data <=  {I_dev_addr, 1'b0}  ;
                        R_state     <=  4'd3                ; // 加载完设备物理地址以后进入起始状态
                        R_jump_state <=  R_state + 1'b1     ; 
                    end
                4'd2   :   // 加载IIC设备字地址                     
                    begin                                   
                        R_load_data <=  I_word_addr         ; 
                        R_state     <=  4'd4                ;
                        R_jump_state <=  R_state + 5'd5      ; // 设置这里是为了这一轮发送并应答后跳到第二次启始位
                    end 
                4'd3    :   // 发送第一个起始信号
                    begin
                        R_scl_en    <=  1'b1                ; // 打开时钟
                        R_sda_mode  <=  1'b1                ; // 设置SDA的模式为输出
                        if(W_scl_high_mid)
                            begin
                                R_sda_reg   <=  1'b0        ; // 在SCL高电平的正中间把SDA引脚拉低产生一个下降沿
                                R_state     <=  4'd4        ; // 下一个状态是发送一个字节数据(IIC设备的物理地址) 
                            end
                        else
                            R_state <=  4'd3                ;    
                    end                      
                4'd4    :   // 发送一个字节
                    begin
                        R_scl_en    <=  1'b1                ; // 打开时钟
                        R_sda_mode  <=  1'b1                ; // 设置SDA的模式为输出
                        if(W_scl_low_mid)                     // 在SCL低电平的最中间改变数据
                            begin
                                if(R_bit_cnt == 4'd8)
                                    begin
                                        R_bit_cnt  <=  4'd0 ;  
                                        R_state    <=  4'd5 ;
                                    end 
                                else
                                    begin
                                        R_sda_reg  <=  R_load_data[7-R_bit_cnt] ;
                                        R_bit_cnt  <=  R_bit_cnt + 1'b1        ; 
                                    end     
                            end
                        else
                            R_state <=  4'd4    ;    
                    end
                4'd5    :   // 接收应答状态应答位
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_reg   <=  1'b0 ;
                        R_sda_mode  <=  1'b0 ; // 设置SDA的模式为输入
                        if(W_scl_high_mid)  
                            begin
                                R_ack_flag  <=  IO_sda  ;
                                R_state     <=  4'd6    ;                                   
                            end
                        else
                            R_state <=  4'd5    ;    
                    end                      
                4'd6    :   // 校验应答位
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟 
                        if(R_ack_flag   == 1'b0)    // 校验通过
                            begin
                                if(W_scl_neg == 1'b1)
                                    begin
                                        R_state <=  R_jump_state ;
                                        R_sda_mode  <=  1'b1 ; // 设置SDA的模式为输出
                                        R_sda_reg   <=  1'b1 ; // 设置SDA的引脚电平拉高，方便后面产生第二次起始位
                                    end
                                else
                                    R_state <= 4'd6    ;
                            end
                        else
                            R_state <=  4'd0 ;    
                    end 
                4'd7    :   // 第二次起始位(IIC读操作要求有2次起始位) 
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_mode  <=  1'b1 ; // 设置SDA的模式为输出 
                        if(W_scl_high_mid)
                            begin
                                R_sda_reg   <=  1'b0  ;
                                R_state     <=  4'd8  ; 
                            end
                        else
                            R_state <=  4'd7 ;    
                    end 
                4'd8   :   // 再次加载IIC设备物理地址 ，但这次地址最后一位应该为1，表示读操作                    
                    begin                                   
                        R_load_data     <=  {I_dev_addr, 1'b1}  ; // 前7bit是设备物理地址，最后一位1表示读操作
                        R_state         <=  4'd4      　　　　　　;
                        R_jump_state    <=  4'd9      　　　　　　; // 设置这里是为了这一轮发送并应答后跳到第二次启始位
                    end
                4'd9    :   // 读一个字节数据
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_mode  <=  1'b0 ; // 设置SDA的模式为输入
                        if(W_scl_high_mid)
                            begin
                                if(R_bit_cnt == 4'd7)
                                    begin
                                        R_bit_cnt    <=  4'd0    ;
                                        R_state      <=  4'd10   ;  
                                        O_read_data  <=  {R_read_data_reg[6:0],IO_sda}  ;                                           
                                    end
                                else
                                    begin
                                        R_read_data_reg  <=  {R_read_data_reg[6:0],IO_sda}  ;
                                        R_bit_cnt        <=  R_bit_cnt   +   1'b1            ;  
                                    end    
                            end 
                        else
                            R_state <=  4'd9 ;    
                    end 
                4'd10    :  // 读完一个字节数据以后进入10，主机发送一个非应答信号1
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_mode  <=  1'b1 ; // 设置SDA的模式为输入
                        if(W_scl_low_mid)
                            begin
                                R_state     <=  4'd11   ; 
                                R_sda_reg    <=    1'b1     ;
                            end 
                        else
                            R_state <=  4'd10 ;    
                    end 
                4'd11   :  
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_mode  <=  1'b1 ; // 设置SDA的模式为输入
                        if(W_scl_low_mid)
                            begin
                                R_state     <=  4'd12   ; 
                                R_sda_reg    <=    1'b0     ;
                            end
                        else
                            R_state <=  4'd11   ;    
                    end 
                4'd12   : //停止位Stop
                    begin
                        R_scl_en    <=  1'b1 ; // 打开时钟
                        R_sda_mode  <=  1'b1 ; // 设置SDA的模式为输出
                        if(W_scl_high_mid)
                            begin
                                R_sda_reg   <=  1'b1    ;
                                R_state     <=  4'd13   ; 
                            end
                        else
                            R_state <=  4'd12   ;    
                    end 
                4'd13   :
                    begin
                        R_scl_en        <=  1'b0 ; // 关闭SCL时钟线
                        R_sda_mode      <=  1'b1 ; // 设置SDA为输出
                        R_sda_reg       <=  1'b1 ; // 拉高SDA保持空闲状态情况
                        O_done_flag     <=  1'b1 ;
                        R_state         <=  4'd0 ;
                        R_read_data_reg <=  8'd0 ;
                    end 
                default: R_state         <=  4'd0 ;
            endcase
        end 
    else
        begin
            R_state         <=  4'd0 ;
            R_sda_mode      <=  1'b1 ;
            R_sda_reg       <=  1'b1 ;
            R_bit_cnt       <=  4'd0 ;
            O_done_flag     <=  1'b0 ;
            R_jump_state    <=  4'd0 ;
            R_read_data_reg <=  8'd0 ;
            R_ack_flag         <=  1'b0 ;
        end
end

wire    [35:0]    CONTROL0 ;
wire    [54:0]    TRIG0 ;
icon icon_inst (
    .CONTROL0(CONTROL0) // INOUT BUS [35:0]
);

ila ila_inst (
    .CONTROL(CONTROL0), // INOUT BUS [35:0]
    .CLK(I_clk), // IN
    .TRIG0(TRIG0) // IN BUS [49:0]
);

assign TRIG0[0] = O_scl ;
assign TRIG0[1] = IO_sda ;
assign TRIG0[11:2] = R_scl_cnt ;
assign TRIG0[12] = R_scl_en ;
assign TRIG0[16:13] = R_state ;
assign TRIG0[17] = R_sda_mode ;
assign TRIG0[18] = R_sda_reg ;
assign TRIG0[26:19] = R_load_data ;

assign TRIG0[30:27] = R_bit_cnt ;
assign TRIG0[31] = R_ack_flag ;
assign TRIG0[36:32] = R_jump_state ;
assign TRIG0[37] = W_scl_low_mid ;
assign TRIG0[38] = W_scl_high_mid ;
assign TRIG0[39] = O_done_flag ;
assign TRIG0[40] = I_rst_n ;
assign TRIG0[48:41] = O_read_data ;
assign TRIG0[49] = W_scl_neg ;


endmodule

