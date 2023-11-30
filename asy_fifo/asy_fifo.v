//Asy_fifo's significance is that do data exchange with fifo;
//concept: fifo's width and depth
//  width:such as 32bit or 16bit,it is up to you.
//  deept:May can calculate by the suddent burst
//*******************Calculate the max deepth
// Eg: wclk--100Mhz,while rclk--50Mhz;the max burst is 120;then 
// wtime = 1/100MHz = 10ns; rtime = 1/50Mhz = 20ns;
// w120_time = 120 * 10 ==1200ns,while read data is 1200/20ns = 60;
// 120 - 60 = 60; So the min deepth is 60;

// 1 CDC-solve-1bit
```verilog
module cdc_1bit(
    input clk_a,
    input clk_b,
    input wire data,
    output reg dout
);
reg q1,q2,q3;
always @(posedge clk_a) begin
    q1 <= data;
end
    
always @(posedge clk_b) begin
    q2 <= q1;
    q3 <= q2;
end
assign dout = q3;

endmodule
```
// 2 CDC-solve-multi_bit
// Asy_fifo state: full,empty,almost_full,almost_empty;
// For patameter and module;
// Asy_fifo will be consisted of fifo_mem and fifo_ctrl;
```verilog
module fifo #(
    parameter DSIZE = 8;
    parameter ASIZE = 4;
)(
    input [DSIZE-1:0] wdata;
    input wclk,
    input wrst_n,
    input winc,
    input rclk,
    input rrst_n,
    input rinc,

    output [DSIZE-1:0] rdata;
    output wfull,
    output rempty
);
    wire [ASIZE -1:0] waddr,raddr;
    wire [ASIZE :0] wptr,rptr,wq2_rptr,rq2_wptr;
    //synchronize the read pointer into the write-clock domain
    sync_r2w    sync_r2w_u(
        //TODO
    );
    //synchronize the write pointer into teh read-clock domain
    sync_w2r    sync_w2r_u(
        //TODO
    );
    //this is the FIFO memory buffer that is accessed by both the write and read clk domain.
    //the buffer is likely an instantiated,synchrouous dual-port ram.
    fifomem #(DSIZE,ASIZE) fifomem_u(
        //TODO

    );
    //the blk is compeletely synch to the rd clk domain and contains teh FIFO rd pointer and output the empty-flag logic.
    rptr_empty #(ASIZE) rptr_empty(
        //TODO
    );
    //the blk is completely synch to the wr_clk domain and conatains the FIFO wr pointer and full-flag logic.
    wptr_full #(ASIZE) wptr_full(
        //TODO
    );
endmodule

// fifomem.v blk
module fifomem #(
    parameter DATASIZE = 8; // memory data word width
    parameter ADDRSIZE = 4; // if depth is 8,then 3 is ok,the left bit is used to judge full or empty
)(
    input [ADDRSIZE-1:0] waddr,raddr,
    input [DATASIZE-1:0] wdata,
    input wclken,wfull,wclk,
    output [DATASIZE-1:0] rdata
);
    `ifdef RAM  // if can use ram IP
        my_ram mem(
            .dout(rdata),
            .din(wdata),
            .waddr(waddr),
            .raddr(raddr),
            .wclken(wclken),
            .wfull(wfull),
            .clk(wclk)
        );
    `else   // use Array
     localparam DEPTH = 1<<ADDRSIZE;    //means  mul
     reg [DATASIZE-1:0] mem [0:DEPTH-1];
     always @(posedge wclk) begin
         if(wclken && !wfull) begin
             mem[waddr] <= wdata;
         end
     end
    `endif

endmodule
//sync_r2w.v
```verilog
module sync_r2w #(
    parameter ADDRSIZE = 4;
)(
    output reg [ADDRSIZE:0] wq2_rptr,//rptr sync to wclk
    input [ADDRSIZE:0] rptr,    //gray's rptro
    input wclk,
    input wrst_n
);
    reg [ADDRSIZE:0] wq1_rptr;

    always @(posedge wclk or negedge wrst_n) begin
        if(!wrst_n) begin
            wq1_rptr <= 0;
            wq2_rptr <= 0;
        end else begin
            wq1_rptr <= rptr;
            wq2_rptr <= wq1_rptr;
        end
    end
endmodule
```
//sync_w2r.v

module sync_w2r #(
    parameter ADDRSIZE = 4;
)(
    output reg [ADDRSIZE:0] rq2_wptr,//wptr sync to rclk
    input [ADDRSIZE:0] wptr,    //gray's wptr
    input rclk,
    input rrst_n
);
    reg [ADDRSIZE:0] rq1_wptr;

    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin
            rq1_wptr <= 0;
            rq2_wptr <= 0;
        end else begin
            rq1_wptr <= wptr;
            rq2_wptr <= rq1_wptr;
        end
    end
endmodule
```
// rptr_empty.v: compare the rq_wptr and rq_rptr to generate
module rptr_empty #(
    parameter ADDRSIZE = 4;
)(
    output reg  empty,
    output [ADDRSIZE-1:0] raddr,//BCD's type
    output reg [ADDRSIZE:0] rptr,//gray's type
    input [ADDRSIZE:0]  rq2_wptr, 
    input rinc,rclk,rrst_n
);
    reg [ADDRSIZE:0] rbin;
    wire [ADDRSIZE:0] rgraynext,rbinnext;
    //GrayStyle pointer
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin
            rbin <= 0;
            rptr <= 0;
        end else begin
            rbin <= binnext;
            rptr <= rgraynext;
        end
    end
    assign raddr = rbin[ADDRSIZE -1:0];
    assign rbinnext = rbin + (rinc & ~empty);
    assign rgraynext = (rbinnext>>1) ^ rbinnext;// bin-->gray
    //fifo empty when the next rptr == synch wptr or on reset
    assign rempty_val = (rgraynext == rq2_wptr);
    always @(posedge rclk or negedge rrst_n) begin
        if(!rrst_n) begin
            rempty <= 1'b1;
        end else begin
            rempty <= rempty_val;
        end
    end
endmodule

// wptr_full.v compare  sync_r2w.v rptr与wclk_wptr to generate full 
module wptr_full
#(
    parameter ADDRSIZE = 4
) 
(
    output reg                wfull,   
    output     [ADDRSIZE-1:0] waddr,
    output reg [ADDRSIZE  :0] wptr, 
    input      [ADDRSIZE  :0] wq2_rptr,
    input                     winc, wclk, wrst_n
);
  reg  [ADDRSIZE:0] wbin;
  wire [ADDRSIZE:0] wgraynext, wbinnext;
  // GRAYSTYLE2 pointer
  always @(posedge wclk or negedge wrst_n)   
      if (!wrst_n)
          {wbin, wptr} <= 0;   
      else         
          {wbin, wptr} <= {wbinnext, wgraynext};
  // Memory write-address pointer (okay to use binary to address memory) 
  assign waddr = wbin[ADDRSIZE-1:0];
  assign wbinnext  = wbin + (winc & ~wfull);
  assign wgraynext = (wbinnext>>1) ^ wbinnext; //二进制转为格雷码
  //-----------------------------------------------------------------
  assign wfull_val = (wgraynext=={~wq2_rptr[ADDRSIZE:ADDRSIZE-1],wq2_rptr[ADDRSIZE-2:0]}); //当最高位和次高位不同其余位相同时则写指针超前于读指针一圈，即写满。后面会详细解释。
  always @(posedge wclk or negedge wrst_n)
      if (!wrst_n)
          wfull  <= 1'b0;   
      else     
          wfull  <= wfull_val;
 
  endmodule

```verilog
module fifo_ctrl #(
    parameter Addr_Width = 5;

)(
    input          reset_n,
    input          wr_clk,
    input          wr_ena,
    input          rd_clk,
    input          rd_ena,
    output         empty,
    output         full,
    output         full,
    output[Addr_Width:0]   wr_addr_ptr,
    output[Addr_Width:0]   rd_addr_ptr

);
    //declare
    reg     wr_rstn;
    reg     rd_rstn;
    reg[Addr_Width:0]     wr_addr_count;
    reg[Addr_Width:0]     rd_addr_count;
    wire[Addr_Width:0]    wr_addr_gray;
    reg[Addr_Width:0]     wr_addr_gray_reg1;
    reg[Addr_Width:0]     wr_addr_gray_reg2;
    wire[Addr_Width:0]    rd_addr_gray;
    reg[Addr_Width:0]     rd_addr_gray_reg1;
    reg[Addr_Width:0]     rd_addr_gray_reg2;

    //wptr_controller
    always @() begin
    end
endmodule
```
