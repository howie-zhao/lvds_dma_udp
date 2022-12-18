`define ZYNQ_PS_EMIO_IIC 1

/**************************************************************************************/
module lvds_recv #(
    parameter DW = 15
)(
    input wire [DW-1:0] DATA_P, //����15λ�����źŵ�p��
    input wire [DW-1:0] DATA_N, //����15λ�����źŵ�n��
    input wire D_GROUP, //ָʾ��ǰ���������ĸ���
    // IIC interface
`ifndef ZYNQ_PS_EMIO_IIC
    output wire SCL,
    inout wire SDA,
`endif
    // Clock and reset
    input wire clk, //ģ��ʱ��
    input wire rst_n, //ģ�鸴λ�ź�
    input wire CLK_P, //����A1100������ʱ�ӣ������pdata��һ�����ͺ�
    input wire CLK_N, 
    output wire RST_D, //��A1100���ֲ��ֵĸ�λ�ź� RSTN
    output wire RST_A  //��A1100ģ�ⲿ�ֵĸ�λ�ź� XSHUTDOWN
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