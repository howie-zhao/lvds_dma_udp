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

/**************************************************************************************/



/**************************************************************************************/

endmodule //lvds_recv