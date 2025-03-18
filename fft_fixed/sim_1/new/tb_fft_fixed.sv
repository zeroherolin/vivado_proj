`timescale 1ns / 1ps

`define CPLX_WIDTH (16 + 16)
`define FFT_LENGTH 1024

module tb_fft_fixed();

reg clk;
reg rst_n;

always #5 clk = ~clk; // 100MHz

reg  [15:0]            s_axis_config_tdata;
reg                    s_axis_config_tvalid;
wire                   s_axis_config_tready;

reg  [`CPLX_WIDTH-1:0] s_axis_data_tdata;
reg                    s_axis_data_tvalid;
wire                   s_axis_data_tready;
reg                    s_axis_data_tlast;

wire [`CPLX_WIDTH-1:0] m_axis_data_tdata;
wire [7:0]             m_axis_data_tuser;
wire                   m_axis_data_tvalid;
reg                    m_axis_data_tready;
wire                   m_axis_data_tlast;

wire [7:0]             m_axis_status_tdata;
wire                   m_axis_status_tvalid;
reg                    m_axis_status_tready;

wire                   event_tlast_unexpected;
wire                   event_tlast_missing;
wire                   event_fft_overflow;
wire                   event_status_channel_halt;
wire                   event_data_in_channel_halt;
wire                   event_data_out_channel_halt;

xfft_0 dut (
    .aclk(clk),                                                 // input wire aclk
    .aresetn(rst_n),                                            // input wire aresetn

    .s_axis_config_tdata(s_axis_config_tdata),                  // input wire [15 : 0] s_axis_config_tdata
    .s_axis_config_tvalid(s_axis_config_tvalid),                // input wire s_axis_config_tvalid
    .s_axis_config_tready(s_axis_config_tready),                // output wire s_axis_config_tready

    .s_axis_data_tdata(s_axis_data_tdata),                      // input wire [31 : 0] s_axis_data_tdata
    .s_axis_data_tvalid(s_axis_data_tvalid),                    // input wire s_axis_data_tvalid
    .s_axis_data_tready(s_axis_data_tready),                    // output wire s_axis_data_tready
    .s_axis_data_tlast(s_axis_data_tlast),                      // input wire s_axis_data_tlast

    .m_axis_data_tdata(m_axis_data_tdata),                      // output wire [31 : 0] m_axis_data_tdata
    .m_axis_data_tuser(m_axis_data_tuser),                      // output wire [7 : 0] m_axis_data_tuser
    .m_axis_data_tvalid(m_axis_data_tvalid),                    // output wire m_axis_data_tvalid
    .m_axis_data_tready(m_axis_data_tready),                    // input wire m_axis_data_tready
    .m_axis_data_tlast(m_axis_data_tlast),                      // output wire m_axis_data_tlast

    .m_axis_status_tdata(m_axis_status_tdata),                  // output wire [7 : 0] m_axis_status_tdata
    .m_axis_status_tvalid(m_axis_status_tvalid),                // output wire m_axis_status_tvalid
    .m_axis_status_tready(m_axis_status_tready),                // input wire m_axis_status_tready

    .event_frame_started(event_frame_started),                  // output wire event_frame_started
    .event_tlast_unexpected(event_tlast_unexpected),            // output wire event_tlast_unexpected
    .event_tlast_missing(event_tlast_missing),                  // output wire event_tlast_missing
    .event_fft_overflow(event_fft_overflow),                    // output wire event_fft_overflow
    .event_status_channel_halt(event_status_channel_halt),      // output wire event_status_channel_halt
    .event_data_in_channel_halt(event_data_in_channel_halt),    // output wire event_data_in_channel_halt
    .event_data_out_channel_halt(event_data_out_channel_halt)   // output wire event_data_out_channel_halt
);

reg [`CPLX_WIDTH-1:0] input_data [0:`FFT_LENGTH-1];
reg [`CPLX_WIDTH-1:0] output_data [0:`FFT_LENGTH-1];
wire signed [`CPLX_WIDTH/2-1:0] output_real;
wire signed [`CPLX_WIDTH/2-1:0] output_imag;
wire signed [`CPLX_WIDTH-1:0] output_sq;
assign output_real = m_axis_data_tdata[`CPLX_WIDTH/2-1:0];
assign output_imag = m_axis_data_tdata[`CPLX_WIDTH-1:`CPLX_WIDTH/2];
assign output_sq = output_real*output_real + output_imag*output_imag;

initial begin
    initialize_system();
    run_test();
    $finish;
end

task initialize_system;
begin
    clk = 1'b0;
    rst_n = 1'b1;

    s_axis_config_tvalid = 1'b0;
    s_axis_data_tvalid = 1'b0;
    s_axis_data_tlast = 1'b0;
    m_axis_data_tready = 1'b0;
    m_axis_status_tready = 1'b0;

    initialize_config();
    initialize_input_data();

    #10;
    rst_n = 1'b0;
    #100;
    rst_n = 1'b1;
    #100;
end
endtask

task initialize_config;
begin
    s_axis_config_tdata = {5'b00000, 10'b10_10_10_10_10, 1'b1};
end
endtask

task initialize_input_data;
    integer real_file, imag_file;
    integer status_r, status_i;
    shortreal real_val, imag_val;
    integer scaled_real_val, scaled_imag_val;
    reg signed [15:0] real_to_q1_15, imag_to_q1_15;
begin
    real_file = $fopen("/home/xilinx/Desktop/fft_fixed/input_x_real.txt", "r");
    imag_file = $fopen("/home/xilinx/Desktop/fft_fixed/input_x_imag.txt", "r");

    if (!real_file || !imag_file) begin
        $display("Error opening input files!");
        $finish;
    end

    for(int i=0; i<`FFT_LENGTH; i++) begin
        status_r = $fscanf(real_file, "%f", real_val);
        status_i = $fscanf(imag_file, "%f", imag_val);

        if (status_r != 1 || status_i != 1) begin
            $display("Error reading data at line %0d", i);
            $finish;
        end

        scaled_real_val = $rtoi(real_val * 32768.0);
        scaled_real_val = (scaled_real_val > 32767) ? 32767 : 
                         (scaled_real_val < -32768) ? -32768 : scaled_real_val;
        real_to_q1_15 = scaled_real_val[15:0];

        scaled_imag_val = $rtoi(imag_val * 32768.0);
        scaled_imag_val = (scaled_imag_val > 32767) ? 32767 : 
                          (scaled_imag_val < -32768) ? -32768 : scaled_imag_val;
        imag_to_q1_15 = scaled_imag_val[15:0];

        input_data[i] = {
            imag_to_q1_15,
            real_to_q1_15
        };
    end

    $fclose(real_file);
    $fclose(imag_file);
end
endtask

task run_test;
begin
    send_configuration();
    send_input_frame();
    receive_output_frame();
    post_process();
    #1000;
end
endtask

task send_configuration;
begin
    $display("[%0t] Sending configuration...", $time);
    s_axis_config_tvalid = 1'b1;

    while (!s_axis_config_tready) @(posedge clk);
    @(posedge clk);
    s_axis_config_tvalid <= 1'b0;
    $display("[%0t] Configuration sent", $time);
end
endtask

task send_input_frame;
integer data_counter;
begin
    $display("[%0t] Sending input data...", $time);
    data_counter = 0;

    while (data_counter < `FFT_LENGTH) begin
        s_axis_data_tvalid <= 1'b1;
        s_axis_data_tdata <= input_data[data_counter];
        s_axis_data_tlast <= (data_counter == `FFT_LENGTH-1);

        if (s_axis_data_tready) begin
            $display("Sent data[%0d] = %h", data_counter, s_axis_data_tdata);
            data_counter++;
        end

        @(posedge clk);
    end

    s_axis_data_tvalid <= 1'b0;
    s_axis_data_tlast <= 1'b0;
    $display("[%0t] Input data sent complete", $time);
end
endtask

task receive_output_frame;
integer out_file;
integer output_counter;
begin
    $display("[%0t] Receiving output data...", $time);
    out_file = $fopen("/home/xilinx/Desktop/fft_fixed/output_results.txt", "w");
    m_axis_data_tready = 1'b1;
    output_counter = 0;

    while (output_counter < `FFT_LENGTH) begin
        if (m_axis_data_tvalid) begin
            output_data[output_counter] <= m_axis_data_tdata;

            $fwrite(out_file, "Real: %d Imag: %d\n",
                $signed(m_axis_data_tdata[`CPLX_WIDTH/2-1:0]),
                $signed(m_axis_data_tdata[`CPLX_WIDTH-1:`CPLX_WIDTH/2])
            );

            $display("Received data[%0d] = %h", output_counter, m_axis_data_tdata);

            if (m_axis_data_tlast) begin
                $display("Detected TLAST at position %0d", output_counter);
            end

            output_counter++;
        end
        @(posedge clk);
    end
    
    $fclose(out_file);
    $display("[%0t] Output data received complete", $time);
end
endtask

task post_process;
begin
    if (event_fft_overflow) begin
        $display("[ERROR] FFT overflow detected!");
    end

    if (event_tlast_unexpected) begin
        $display("[ERROR] Unexpected TLAST detected!");
    end

    if (event_tlast_missing) begin
        $display("[ERROR] Missing TLAST detected!");
    end

    verify_fft_results();
end
endtask

task verify_fft_results;
begin

end
endtask

endmodule
