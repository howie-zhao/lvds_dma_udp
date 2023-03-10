`define ZYNQ_PS_EMIO_IIC 1
/**************************************************************************************/
module lvds_recv #(
    parameter DW = 15,
    parameter FRAME_NUM = 1024,//一帧UDP数据包的字节数
    parameter M_AXIS_TDATA_WIDTH = 32
)(
    input wire [DW-1:0] DATA_P, //输入15位数据信号的p端
    input wire [DW-1:0] DATA_N, //输入15位数据信号的n端
    input wire D_GROUP, //指示当前数据来自哪个组
    // IIC interface
`ifndef ZYNQ_PS_EMIO_IIC
    output wire SCL,
    inout wire SDA,
    output wire RST_D, //给A1100数字部分的复位信号 RSTN
    output wire RST_A,  //给A1100模拟部分的复位信号 XSHUTDOWN
`endif
    // Clock and reset
    input wire clk, //模块时钟 100M
    input wire rst_n, //模块复位信号
    input wire CLK_P, //来自A1100的输入时钟，相对于pdata有一定的滞后 频率：250M 125M 62.5M
    input wire CLK_N, 
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
    // IIC Drive
    assign sda_en = sda_o;
    assign SCL = sclk;
    assign SDA = sda_en ? 1'bz : sda_o;
    assign sda_i = SDA;
    // RST Drive
    assign RST_D = 1;
    assign RST_A = 1;
`endif
    // DATA signals
    wire [DW-1:0] DATA_IN; //单端数据信号
    wire CLK_IN; //单端时钟信号
    reg [DW-1:0] data_r;
    reg group_r;
    
    // FIFO signals
    wire [DW:0] fifo_wr_data;
    reg fifo_wr_en;
    reg [7:0] fifo_wr_cnt;
    wire fifo_rd_en;
    reg [1:0] fifo_rd_en_d;
    wire [M_AXIS_TDATA_WIDTH-1:0] fifo_rd_data;
    wire empty;
    wire full;
    wire overflow, underflow;
    wire [10:0] rd_data_cnt;
    wire prog_full;

    // Interface and Logic signals
    reg tx_valid;
    reg [8:0] tx_cnt;
    wire tx_done;
    reg [M_AXIS_TDATA_WIDTH-1:0] tx_data;
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
//异步FIFO，packet mode,深度8192字节
//WR 16 x 4096
//RD 32 x 2048
    fifo_generator_0 u_fifo_recv(
        .wr_clk       (CLK_IN),
        .rd_clk       (M_AXIS_ACLK),
        .rst          (~rst_n),
        .wr_en        (fifo_wr_en),
        .rd_en        (fifo_rd_en),
        .din          (fifo_wr_data),  //width 16
        .dout         (fifo_rd_data),  //width 32
        .empty        (empty),
        .full         (full),
        .overflow     (overflow),
        .underflow    (underflow),
        .rd_data_count(rd_data_cnt),//1~2048
        .prog_full    (prog_full),//阈值 512x2=1024字节
        .wr_rst_busy  (),
        .rd_rst_busy  ()
    );
/**************************************************************************************/
//FIFO的 AXI stream 接口设计
//1帧数据写入后，拉高输出valid，等待后续DMA的ready（read enable）信号
//需要在一帧数据结束时拉高tlast信号

    assign M_AXIS_TVALID = fifo_rd_en_d[1]; //读FIFO有1个cycle的latency
    assign M_AXIS_TLAST = tx_done;
    assign M_AXIS_TDATA = tx_data;
    assign M_AXIS_TSTRB = {(M_AXIS_TDATA_WIDTH/8){1'b1}};

    always @(posedge M_AXIS_ACLK) begin
        if(!M_AXIS_ARESETN) begin
            tx_valid <= 0;
        end
        //packet mode
        //读FIFO中有一帧数据时，读有效
        else if(rd_data_cnt >= (FRAME_NUM/4)) begin
            tx_valid <= 1;
        end
        else if(tx_done) begin
            tx_valid <= 0;
        end
    end
    assign fifo_rd_en = tx_valid & M_AXIS_TREADY;
    always @(posedge M_AXIS_ACLK) begin
        if(!M_AXIS_ARESETN) begin
            fifo_rd_en_d[1:0] <= 0;
        end
        else begin
            fifo_rd_en_d[1:0] <= {fifo_rd_en_d[0], fifo_rd_en};
        end
    end
    always @(posedge M_AXIS_ACLK) begin
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
    assign tx_done = (tx_cnt == (FRAME_NUM/4));//一帧包括1024字节，数据位宽为4字节，总共256个数据
endmodule //lvds_recv