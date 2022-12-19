`define ZYNQ_PS_EMIO_IIC 1

/**************************************************************************************/
module lvds_recv #(
    parameter DW = 15
)(
    input wire [DW-1:0] DATA_P, //输入15位数据信号的p端
    input wire [DW-1:0] DATA_N, //输入15位数据信号的n端
    input wire D_GROUP, //指示当前数据来自哪个组
    // IIC interface
`ifndef ZYNQ_PS_EMIO_IIC
    output wire SCL,
    inout wire SDA,
`endif
    // Clock and reset
    input wire clk, //模块时钟
    input wire rst_n, //模块复位信号
    input wire CLK_P, //来自A1100的输入时钟，相对于pdata有一定的滞后
    input wire CLK_N, 
    output wire RST_D, //给A1100数字部分的复位信号 RSTN
    output wire RST_A  //给A1100模拟部分的复位信号 XSHUTDOWN
);
/**************************************************************************************/
`ifndef ZYNQ_PS_EMIO_IIC
    wire sclk;
    wire sda_en;
    wire sda_i;
    wire sda_o;
    assign sda_en = sda_o;
    assign SCL = sclk;
    assign SDA = sda_en ? 1'bz : sda_o;
    assign sda_i = SDA; 
`endif
    wire [DW-1:0] DATA_IN; //单端数据信号
    wire CLK_IN; //单端时钟信号
    reg [DW-1:0] data_r;
    reg group_r;
/**************************************************************************************/
//差分输入转单端
    genvar i;
    generate
        for(i=0; i<DW; i=i+1) begin
            //差分输入BUF原语
            IBUFDS #(
                .DIFF_TERM("TRUE"),
                .IOSTANDARD("LVDS_25")
            ) u_dbufds (
                .O(DATA_IN[i]),
                .I(DATA_P[i]),
                .IB(DATA_N[i])
            );
        end

        IBUFGDS #(
            .DIFF_TERM("TRUE"),
            .IOSTANDARD("LVDS_25")
        ) u_cbufds (
            .O(CLK_IN),
            .I(CLK_P),
            .IB(CLK_N)
        );
    endgenerate

    always @(posedge CLK_IN or negedge rst_n) begin
        if(!rst_n) begin
            data_r <= 0; //TODO：改为同步复位或取消复位
            group_r <= 0;
        end
        else begin
            data_r <= DATA_IN;
            group_r <= D_GROUP;     
        end
    end
/**************************************************************************************/

endmodule //lvds_recv