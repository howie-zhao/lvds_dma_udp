`define ZYNQ_PS_EMIO_IIC 1

/**************************************************************************************/
module lvds_recv #(
    parameter DW = 15,
    parameter FRAME_NUM = 1024,
    parameter AXI_DW = 32
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
    input wire clk, //模块时钟 100M
    input wire rst_n, //模块复位信号
    input wire CLK_P, //来自A1100的输入时钟，相对于pdata有一定的滞后 频率：250M 125M 62.5M
    input wire CLK_N, 
    output wire RST_D, //给A1100数字部分的复位信号 RSTN
    output wire RST_A,  //给A1100模拟部分的复位信号 XSHUTDOWN
    // AXI Stream Interface
    input wire m_aclk,
    input wire m_aresetn,
    input wire m_axis_tready,
    output wire m_axis_tvalid,
    output wire m_axis_tlast,
    //output wire m_axis_tuser,
    //output wire m_axis_tkeep,
    output wire [AXI_DW-1:0] m_axis_tdata
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
    wire [DW:0] fifo_wr_data;
    reg fifo_wr_en;
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
            .O(CLK_IN), // 250M max
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
        else if (fifo_wr_cnt == 512) begin //一次传输有512+1个时钟周期，第一个周期无效
            fifo_wr_cnt <= 10'b0;
        end
        else begin
            fifo_wr_cnt <= fifo_wr_cnt + 1;
        end
    end
/**************************************************************************************/
//异步FIFO，packet mode
    fifo u_fifo_recv(
        .wr_clk       (CLK_IN),
        .rd_clk       (m_aclk),
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
//FIFO的 AXI stream 接口设计
//1帧数据写入后，拉高输出valid，等待后续DMA的ready（read enable）信号
//需要在一帧数据结束时拉高tlast信号

    assign m_axis_tvalid = fifo_rd_en_d[1]; //读FIFO有1个cycle的latency
    assign m_axis_tlast = tx_done;
    assign m_axis_tdata = tx_data;

    always @(posedge m_aclk or negedge m_aresetn) begin
        if(!m_aresetn) begin
            tx_valid <= 0;
        end
        else if(rd_data_cnt >= FRAME_NUM) begin
            tx_valid <= 1;
        end
        else if(tx_done) begin
            tx_valid <= 0;
        end
    end
    assign fifo_rd_en = tx_valid & m_axis_tready;
    always @(posedge m_aclk or negedge m_aresetn) begin
        if(!m_aresetn) begin
            fifo_rd_en_d[1:0] <= 0;
        end
        else begin
            fifo_rd_en_d[1:0] <= {fifo_rd_en_d[0], fifo_rd_en};
        end
    end
    always @(posedge m_aclk or negedge m_aresetn) begin
        if(!m_aresetn) begin
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