module parity_gen #(
    parameter DATA_WIDTH = 8,
    parameter PARITY_TYPE = 1,
)(
    input                   sys_clk,
    input                   sys_rst_n,
    input[DATA_WIDTH -1:0]   data_in,
    input                   data_valid,// only the outside data valid 

    output reg              parity
);
    //Parameter
    parameter   PARITY_TYPE_EVEN  = 1;  //even parity
    parameter   PARITY_TYPE_ODD  = 2;  //odd parity
    parameter   PARITY_TYPE_MARK0  = 3;  //fixed parity 0
    parameter   PARITY_TYPE_MARK1  = 4;  //fixed parity 0

    // paritey generate logic
    always  @(posedge sys_clk or negedge sys_rst_n)begin
        if(rst_n==1'b0)begin
            parity <= 0;
        end
        else begin
            if(data_valid) begin
                case(PARITY_TYPE)
                    PARITY_TYPE_EVEN : parity <= ~data_in;
                    PARITY_TYPE_ODD :  parity <= ^data_in;
                    PARITY_TYPE_MARK0 :  parity <= 0;
                    PARITY_TYPE_MARK1 :  parity <= 1;
                    default: parity = ~data_in;
                endcase
            end else begin
                    parity <= 0;
            end
        end
    end

endmodule
