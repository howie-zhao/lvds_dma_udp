`define ZYNQ_PS_EMIO_IIC 1

/**************************************************************************************/
module lvds_recv #(
    parameter DW = 15,
    parameter FRAME_NUM = 1024,
    parameter M_AXIS_TDATA_WIDTH = 32
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
    input wire clk, //ģ��ʱ�� 100M
    input wire rst_n, //ģ�鸴λ�ź�
    input wire CLK_P, //����A1100������ʱ�ӣ������pdata��һ�����ͺ� Ƶ�ʣ�250M 125M 62.5M
    input wire CLK_N, 
    output wire RST_D, //��A1100���ֲ��ֵĸ�λ�ź� RSTN
    output wire RST_A,  //��A1100ģ�ⲿ�ֵĸ�λ�ź� XSHUTDOWN
    // AXI Stream Interface
    input wire M_AXIS_ACLK,
    input wire M_AXIS_ARESETN,
    input wire M_AXIS_TREADY,
    output wire M_AXIS_TVALID,
    output wire M_AXIS_TLAST,
    //output wire M_AXIS_TUSER,
    //output wire M_AXIS_TKEEP,
    output wire [(M_AXIS_TDATA_WIDTH/8)-1:0] M_AXIS_TSTRB,
    output wire [M_AXIS_TDATA_WIDTH-1:0] M_AXIS_TDATA
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
    wire [DW:0] fifo_wr_data;
    reg fifo_wr_en;
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
            .O(CLK_IN), // 250M max
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
    assign fifo_wr_data = {group_r, data_r};
    always @(posedge CLK_IN or negedge rst_n) begin
        if(!rst_n) begin
            fifo_wr_en <= 1'b0;
        end
        else if (fifo_wr_cnt != 0) begin
            fifo_wr_en <= 1'b1;
        end
        else begin
            fifo_wr_en <= 1'b0;
        end
    end

    always @(posedge CLK_IN or negedge rst_n) begin
        if(!rst_n) begin
            fifo_wr_cnt <= 10'b0;
        end
        else if (fifo_wr_cnt == 512) begin //һ�δ�����512+1��ʱ�����ڣ���һ��������Ч
            fifo_wr_cnt <= 10'b0;
        end
        else begin
            fifo_wr_cnt <= fifo_wr_cnt + 1;
        end
    end
/**************************************************************************************/
//�첽FIFO��packet mode
    fifo u_fifo_recv(
        .wr_clk       (CLK_IN),
        .rd_clk       (M_AXIS_ACLK),
        .srst         (~rst_n),
        .wr_en        (fifo_wr_en),
        .rd_en        (fifo_rd_en),
        .din          (fifo_wr_data),
        .dout         (fifo_rd_data),
        .empty        (empty),
        .full         (full),
        .overflow     (overflow),
        .underflow    (underflow),
        .rd_data_count(rd_data_cnt)
    );
/**************************************************************************************/
//FIFO�� AXI stream �ӿ����
//1֡����д����������valid���ȴ�����DMA��ready��read enable���ź�
//��Ҫ��һ֡���ݽ���ʱ����tlast�ź�

    assign M_AXIS_TVALID = fifo_rd_en_d[1]; //��FIFO��1��cycle��latency
    assign M_AXIS_TLAST = tx_done;
    assign M_AXIS_TDATA = tx_data;
    assign M_AXIS_TSTRB = {(M_AXIS_TDATA_WIDTH/8){1'b1}};

    always @(posedge M_AXIS_ACLK or negedge M_AXIS_ARESETN) begin
        if(!M_AXIS_ARESETN) begin
            tx_valid <= 0;
        end
        else if(rd_data_cnt >= FRAME_NUM) begin
            tx_valid <= 1;
        end
        else if(tx_done) begin
            tx_valid <= 0;
        end
    end
    assign fifo_rd_en = tx_valid & M_AXIS_TREADY;
    always @(posedge M_AXIS_ACLK or negedge M_AXIS_ARESETN) begin
        if(!M_AXIS_ARESETN) begin
            fifo_rd_en_d[1:0] <= 0;
        end
        else begin
            fifo_rd_en_d[1:0] <= {fifo_rd_en_d[0], fifo_rd_en};
        end
    end
    always @(posedge M_AXIS_ACLK or negedge M_AXIS_ARESETN) begin
        if(!M_AXIS_ARESETN) begin
            tx_data <= 0;
            tx_cnt <= 0;
        end
        else if(fifo_rd_en_d[0]) begin
            tx_data <= fifo_rd_data;
            tx_cnt <= tx_cnt + 1;
        end
        else if (tx_done) begin
            tx_cnt <= 0;
        end
    end
    assign tx_done = (tx_cnt == FRAME_NUM);
endmodule //lvds_recv