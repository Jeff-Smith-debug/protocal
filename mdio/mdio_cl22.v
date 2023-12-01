module	MDIO
(
    input	rst,
    input	clk,
    
    output reg mdc,
    inout	mdio,

    input                start      ,   //开始传输标志  高电平有效，结束传输后拉低
    input  [1:0]         opcode     ,
    input  [4:0]         phy_addr   ,   //phy address
    input  [4:0]         reg_addr   ,   //phy register address
    input  [15:0]        write_data ,   //write smi data
    
    output reg [15:0]    phy_reg    ,   //read smi data
    output reg           transfer_end   //write or read finished
	
);


reg mdio_oe,mdio_out;
wire mdio_in;

assign mdio = mdio_oe ? mdio_out : 1'bz ;// MDIO数据输出或高阻, 0-READ,1-WRITE
assign mdio_in = mdio;


//产生MDC 时钟
parameter NUM=49;  //50M/100=500k
reg [5:0] cnt;
always @(posedge clk or negedge rst)
begin
	if(!rst)
	begin
		cnt<=0;
		mdc<=0;
	end
	else if (cnt==NUM)
	begin
		cnt<=0;
		mdc<=mdc+1;
	end
	else
	begin
		cnt<=cnt+1;
	end
end


//数据流，上升沿有效
parameter preamble=8'b00000001;
parameter st=	     8'b00000010;
parameter op=      8'b00000100;
parameter phyad=   8'b00001000;
parameter regad=   8'b00010000;
parameter ta=      8'b00100000;
parameter data=    8'b01000000;
parameter idle=    8'b10000000;


//检测上升沿，产生开始传输脉冲
reg  start_next;
wire start_edge;
always @(posedge mdc or negedge rst)
begin
	if(!rst)
	begin
		start_next<=0;
	end
	else 
		start_next<=start;
end

assign start_edge=!start_next & start;  // for check the posedge edge


//状态转移
reg [7:0] state,state_next;

always @(posedge mdc or negedge rst )
begin
	if(!rst)
	begin
		state<=idle;
	end 
	else if(start_edge)
		begin
			state<=preamble;
			
		end
		
	else
		state<=state_next;
end


//接口数据缓存
reg [1:0] st_code;          //mdio start code
reg [1:0] ta_code ;          //mdio write code
reg [1:0] op_code;
reg [4:0] regaddr;
reg [4:0] phyaddr; 
reg [15:0] writedata;



reg [7:0] counter;
always @(posedge mdc or negedge rst)
begin
	if(!rst)
	begin 
		counter<=0;
	end
	else if(counter==64)
	begin
		counter<=0;
		transfer_end<=1;
	end
	else if(state!=idle)
	begin
		transfer_end<=0;
		counter<=counter+1;
	end
		
end


always @(negedge mdc)
begin
	state_next<=state;
	case(state)
	preamble: 
		begin
			st_code<= 2'b01 ; 
			ta_code<= 2'b10 ;
			op_code<=opcode;//缓存
			regaddr<=reg_addr;
			phyaddr<=phy_addr;
			writedata<=write_data;
			mdio_oe<=1;
			mdio_out<=1;
			if(counter==31)
				begin
					state_next<=st;
				end
		end
	st:
		begin
			mdio_oe<=1;
			mdio_out<=st_code[1];
			st_code<=st_code<<1;
			if(counter==33)
				begin
					state_next<=op;
				end
		end
	op:
		begin
			mdio_oe<=1;
			mdio_out<=op_code[1];
			op_code<=op_code<<1;
			if(counter==35)
				begin
					state_next<=phyad;
				end
		end
	phyad:
		begin
			mdio_oe<=1;
			mdio_out<=phyaddr[4];
			phyaddr<=phyaddr<<1;
			if(counter==40)
				begin
					state_next<=regad;
				end
		end
	regad:
		begin
			mdio_oe<=1;
			mdio_out<=regaddr[4];
			regaddr<=regaddr<<1;
			if(counter==45)
				begin
					state_next<=ta;
				end
		end
	ta:
		begin
			if(opcode==2'b10)
			begin
				mdio_oe<=0;
				if(counter==47)
				begin
					state_next<=data;
				end
			end
			if(opcode==2'b01)
			begin
				mdio_oe<=1;
				mdio_out<=ta_code[1];
				ta_code<=ta_code<<1;
				if(counter==47)
				begin
					state_next<=data;
				end
			end
		end
	data:
		begin
			if(opcode==2'b10)//读取
			begin
				mdio_oe<=0;
				//读取放到外面；
				if(counter==63)
				begin
					state_next<=idle;
				end
			end
			if(opcode==2'b01)//写入
			begin
				mdio_oe<=1;
				mdio_out<=writedata[15];
				writedata<=writedata<<1;
				if(counter==63)
				begin
					state_next<=idle;
				end
			end
		end
	idle:
		begin
			mdio_oe<=0;
				if(counter==64)
				begin
					state_next<=idle;
				end
		end
	default:
		begin
			state_next<=idle;
		end
	
endcase
end	
//读取数据
always @(posedge mdc or negedge rst )
begin
	if(!rst)
	begin
		phy_reg<=0;
	end
	else if(state_next==data )
	begin
		phy_reg<={phy_reg[14:0],mdio_in};
	end
	else 
		phy_reg<=phy_reg;
end

endmodule
//  ————————————————
//  版权声明：本文为CSDN博主「石头明月」的原创文章，遵循CC 4.0 BY-SA版权协议，转载请附上原文出处链接及本声明。
//  原文链接：https://blog.csdn.net/yingyu12345/article/details/126129452

