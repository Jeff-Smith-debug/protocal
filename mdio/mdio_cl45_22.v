 `timescale 1ns / 1ps
	//////////////////////////////////////////////////////////////////////////////////
	// Company: 
	// Engineer: 
	// 
	// Create Date: 2019/08/12 10:39:51
	// Design Name: 
	// Module Name: eth_mdio_interface
	// Project Name: 
	// Target Devices: 
	// Tool Versions: 
	// Description: 
	// 
	// Dependencies: 
	// 
	// Revision:
	// Revision 0.01 - File Created
	// Additional Comments:  
	//      
	//////////////////////////////////////////////////////////////////////////////////

module eth_mdio_interface #(
  parameter MDC_DIVISOR = 100     //// MDC frequency is clk_i / MDC_DIVISOR.  

)(

 input               clk_i,
 input               rstn_i,

 input               clause_sel_i,////1 : Clause 45;  0 : Clause 22;

 output  reg         ready_o,
 input               valid_i,
 input   [1:0]       cmd_i,
 input   [25:0]      addr_i,      ////Cl45: PHY Addr(5 bit) + Devices Addr(5 bit) + Reg Addr(16 bit); Cl22 : PHY Addr(5 bit) + Reg Addr(5 bit) + invalid(16 bit)//
 input   [15:0]      wdata_i,  

 output  reg         rdata_vld_o,
 output  reg [15:0]  rdata_o,

 output  reg         mdc_o,
 input               mdio_i,
 output  reg         mdio_o,
 output  reg         mdio_oen_o

);

localparam  WR_CMD = 2'b01;
localparam  RD_CMD = 2'b11; 
localparam  RD_INC = 2'b10;  ////not supported

//---------------------------------------------------------------------------------------------------
// Function - Calculates the log2ceil of the input value
//---------------------------------------------------------------------------------------------------
function integer log2ceil;
  input integer val;
  integer i;
  begin
	 i = 1;
	 log2ceil = 0;

	 while (i < val) begin
  		log2ceil = log2ceil + 1;
  		i = i << 1; 
	 end
  end
endfunction  
////
 
localparam P_MDC_DIVIDE_BITS = log2ceil(MDC_DIVISOR) - 1;    // Need to count to (MDC_DIVISOR/2) - 1   

reg [P_MDC_DIVIDE_BITS-1:0] mdc_divide;  
reg mdc_tick;     
reg mdc_sample;   

//// Divide clock to make MDIO clock  
always @(posedge clk_i, negedge rstn_i) 
  if(!rstn_i)
	 mdc_divide <= 0;
  else if(mdc_divide == 0)      
    mdc_divide <= (MDC_DIVISOR/2) - 1'b1;
  else 
    mdc_divide <= mdc_divide - 1'b1;

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)    
    mdc_o <= 1'b0;
  else if(mdc_divide == 0)
	 mdc_o <= ~mdc_o;

//// Data is output on mdc_tick. Delay it slightly from the clock to ensure setup and hold timing is met
//// Sample read data just before rising edge of MDC
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i) begin
    mdc_tick <= 1'b0;
    mdc_sample <= 1'b0;
  end
  else begin
	 mdc_tick <= ~mdc_o & (mdc_divide==(MDC_DIVISOR/2) - (MDC_DIVISOR/4));
    mdc_sample <= ~mdc_o & (mdc_divide==2);
  end

//// 
wire   [4:0]    cl45_phy_addr = addr_i[25:21];           
wire   [4:0]    cl45_dev_addr = addr_i[20:16];           
wire   [15:0]   cl45_reg_addr = addr_i[15:0];          
wire   [4:0]    cl22_phy_addr = addr_i[25:21];              
wire   [4:0]    cl22_reg_addr = addr_i[20:16];                                                                           

reg    [3:0]    state;
localparam      ST_PREAMBLE1        = 4'd0;
localparam      ST_IDLE1            = 4'd1;
localparam      ST_WR_ADDR_CL45     = 4'd2;
localparam      ST_IDLE2            = 4'd3;
localparam      ST_PREAMBLE2        = 4'd4;
localparam      ST_REWR_ADDR_CL45   = 4'd5;
localparam      ST_WR_ADDR_CL22     = 4'd6;
localparam      ST_WR_DATA          = 4'd7;
localparam      ST_RD_DATA          = 4'd8;

wire  preamble_set_done;
wire  wr_addr_cl45_done;
wire  wr_addr_cl22_done;
wire  rewr_addr_cl45_done;
wire  wr_data_done;
wire  rd_data_done;
reg   wr_rdn_en;
reg   cmd_pending;

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
	 state <= ST_IDLE1;
  else  
  case (state)
    ST_IDLE1               :   if(cmd_pending && mdc_tick)
        	                      state <= ST_PREAMBLE1; 
                               else 
                                 state <= ST_IDLE1;
    ST_PREAMBLE1           :   if(preamble_set_done)     
                                 state <= clause_sel_i? ST_WR_ADDR_CL45 : ST_WR_ADDR_CL22;
                               else 
                                 state <= ST_PREAMBLE1;                              
    ST_WR_ADDR_CL45        :   if(wr_addr_cl45_done)
                                 state <= ST_IDLE2;
                               else 
                                 state <= ST_WR_ADDR_CL45;
    ST_IDLE2               :   if(mdc_tick)    
                                 state <= ST_PREAMBLE2;
                               else 
                                 state <= ST_IDLE2;                           
    ST_PREAMBLE2           :   if(preamble_set_done)
                                 state <= ST_REWR_ADDR_CL45;
                               else 
                                 state <= ST_PREAMBLE2;
    ST_REWR_ADDR_CL45      :   if(rewr_addr_cl45_done)
                                 state <= wr_rdn_en? ST_WR_DATA : ST_RD_DATA;  
                               else 
                                 state <= ST_REWR_ADDR_CL45;
    ST_WR_ADDR_CL22        :   if(wr_addr_cl22_done)
                                 state <= wr_rdn_en? ST_WR_DATA : ST_RD_DATA;   
                               else 
                                 state <= ST_WR_ADDR_CL22;                          
    ST_WR_DATA             :   if(wr_data_done)                               
                                 state <= ST_IDLE1;
                               else 
                                 state <= ST_WR_DATA;                                 
    ST_RD_DATA             :   if(rd_data_done)   
                                 state <= ST_IDLE1;
                               else 
                                 state <= ST_RD_DATA;       
    default                :   state <= ST_IDLE1;
  endcase

wire latch_en;
assign latch_en = (ready_o && valid_i);  

//// wait mdc_tick to start
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    cmd_pending <= 1'b0;
  else if(latch_en)
	 cmd_pending <= 1'b1;
  else if(mdc_tick)
 	 cmd_pending <= 1'b0;

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    wr_rdn_en <= 1'b0;
  else if(latch_en)
	 wr_rdn_en <= (cmd_i == WR_CMD);

reg [5:0]  preamble_cnt;
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    preamble_cnt <= 6'b0;
  else if(state != ST_PREAMBLE1 && state != ST_PREAMBLE2)   
	 preamble_cnt <= 6'b0; 
  else if(mdc_tick)
    preamble_cnt <= preamble_cnt + 6'b1;

assign preamble_set_done = (preamble_cnt == 6'd31) && mdc_tick;

reg [5:0] wr_addr_cl45_cnt;
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    wr_addr_cl45_cnt <= 6'b0;
  else if(state != ST_WR_ADDR_CL45)
    wr_addr_cl45_cnt <= 6'b0;
  else if(mdc_tick)
    wr_addr_cl45_cnt <= wr_addr_cl45_cnt + 6'b1;

assign wr_addr_cl45_done = (wr_addr_cl45_cnt == 6'd31) && mdc_tick; 

reg [4:0] rewr_addr_cl45_cnt;  
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    rewr_addr_cl45_cnt <= 5'b0;
  else if(state != ST_REWR_ADDR_CL45)      
    rewr_addr_cl45_cnt <= 5'b0;
  else if(mdc_tick)
	 rewr_addr_cl45_cnt <= rewr_addr_cl45_cnt + 5'b1;

assign rewr_addr_cl45_done = (rewr_addr_cl45_cnt == 5'd13) && mdc_tick;

reg [4:0] wr_addr_cl22_cnt;
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    wr_addr_cl22_cnt <= 5'b0;
  else if(state != ST_WR_ADDR_CL22)
    wr_addr_cl22_cnt <= 5'b0;
  else if(mdc_tick)
    wr_addr_cl22_cnt <= wr_addr_cl22_cnt + 5'b1;

assign wr_addr_cl22_done = (wr_addr_cl22_cnt == 5'd13) && mdc_tick;

reg [4:0] wr_data_cnt;
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
    wr_data_cnt <= 5'b0;
  else if(state != ST_WR_DATA)
    wr_data_cnt <= 5'b0;
  else if(mdc_tick)
    wr_data_cnt <= wr_data_cnt + 5'b1;

assign wr_data_done = (wr_data_cnt == 5'd17) && mdc_tick;

reg [4:0] rd_data_cnt;
always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
	 rd_data_cnt <= 5'b0;
  else if(state != ST_RD_DATA)
    rd_data_cnt <= 5'b0;
  else if(mdc_tick)
    rd_data_cnt <= rd_data_cnt + 5'b1;

assign rd_data_done = (rd_data_cnt == 5'd17) && mdc_tick; 

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
	 ready_o = 1'b0;
  else 
    ready_o = (state == ST_IDLE1) && (!valid_i) && (!cmd_pending);

reg [1:0] op_code_cl45;
always @(*)
  case (cmd_i)
	 WR_CMD : op_code_cl45 = 2'b01;
	 RD_CMD : op_code_cl45 = 2'b11;
    RD_INC : op_code_cl45 = 2'b10;
	 default : op_code_cl45 = 2'b11;
  endcase

reg [1:0] op_code_cl22;
always @(*)
  case (cmd_i)
	 WR_CMD : op_code_cl22 = 2'b01;
	 RD_CMD : op_code_cl22 = 2'b10;
	 default : op_code_cl22 = 2'b11;
  endcase

reg [31:0] first_wraddr_sfr_cl45;
always @(posedge clk_i)
  if(latch_en)
    first_wraddr_sfr_cl45 <= {2'b00, 2'b00, cl45_phy_addr, cl45_dev_addr, 2'b10, cl45_reg_addr};
  else if((state == ST_WR_ADDR_CL45) && mdc_tick)
	 first_wraddr_sfr_cl45 <= {first_wraddr_sfr_cl45[30:0], 1'b0};

reg [13:0] second_wraddr_sfr_cl45;
always @(posedge clk_i)
  if(latch_en)
	 second_wraddr_sfr_cl45 <= {2'b00, op_code_cl45, cl45_phy_addr, cl45_dev_addr};
  else if((state == ST_REWR_ADDR_CL45) && mdc_tick)
	 second_wraddr_sfr_cl45 <= {second_wraddr_sfr_cl45[12:0], 1'b0};

reg [13:0]  wraddr_sfr_cl22;
always @(posedge clk_i)  
  if(latch_en)
	 wraddr_sfr_cl22 <= {2'b01, op_code_cl22, cl22_phy_addr, cl22_reg_addr};
  else if((state == ST_WR_ADDR_CL22) && mdc_tick)
	 wraddr_sfr_cl22 <= {wraddr_sfr_cl22[12:0], 1'b0};

reg [17:0] wrdata_sfr;
always @(posedge clk_i)
  if(latch_en)
	 wrdata_sfr <= {2'b10, wdata_i};
  else if((state == ST_WR_DATA) && mdc_tick)      
	 wrdata_sfr <= {wrdata_sfr[16:0], 1'b0};

reg [15:0] rddata_sfr;
always @(posedge clk_i)
  if((state == ST_RD_DATA) && mdc_sample)  
	 rddata_sfr <= {rddata_sfr[14:0], mdio_i};

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
	 mdio_o <= 1'b0;
  else case (state)
	 ST_WR_ADDR_CL45    : mdio_o <= first_wraddr_sfr_cl45[31];
    ST_REWR_ADDR_CL45  : mdio_o <= second_wraddr_sfr_cl45[13];
	 ST_WR_ADDR_CL22    : mdio_o <= wraddr_sfr_cl22[13];
	 ST_WR_DATA         : mdio_o <= wrdata_sfr[17];
	 default            : mdio_o <= 1'b1;
  endcase

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i)
	 mdio_oen_o <= 1'b1;
  else 
	 mdio_oen_o <= (state != ST_RD_DATA)&&(state != ST_IDLE1)&&(state != ST_IDLE2);

always @(posedge clk_i, negedge rstn_i)
  if(!rstn_i) begin
    rdata_vld_o <= 1'b0;
    rdata_o <= 16'b0;
   end
  else if(rd_data_done) begin
	 rdata_vld_o <= 1'b1;
    rdata_o <= rddata_sfr;
  end
  else begin
    rdata_vld_o <= 1'b0;
    rdata_o <= rdata_o;
  end


endmodule

