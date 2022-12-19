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
    wire [DW-1:0] DATA_IN; //���������ź�
    wire CLK_IN; //����ʱ���ź�
    reg [DW-1:0] data_r;
    reg group_r;
/**************************************************************************************/
//�������ת����
    genvar i;
    generate
        for(i=0; i<DW; i=i+1) begin
            //�������BUFԭ��
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
            data_r <= 0; //TODO����Ϊͬ����λ��ȡ����λ
            group_r <= 0;
        end
        else begin
            data_r <= DATA_IN;
            group_r <= D_GROUP;     
        end
    end
/**************************************************************************************/

endmodule //lvds_recv