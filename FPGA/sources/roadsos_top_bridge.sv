`timescale 1ns/1ps
// SAFE-Link / RoadSOS: BIDIRECTIONAL FPGA <-> NodeMCU bridge endpoint.
// Same RTL on both Spartan-7 boards; change only VEHICLE_ID.
// FPGA #1 = 16'h0017, FPGA #2 = 16'h0018.
//
// Wireless path:
// FPGA #1 UART <-> ESP8266 #1 )) Wi-Fi/TCP (( ESP8266 #2 <-> FPGA #2 UART
//
// UART: 115200 8N1
// Packet: A5 | EVENT | VEH_H | VEH_L | CRC_H | CRC_L | 5A | 0A
//
// Boolean Board pins:
// rst=J2, emergency_button=J5, accept_button=H2, clear_button=J1
// event_id[7:0]=SW0..SW7
// uart_tx=U11, uart_rx=V12

module roadsos_top #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE = 115_200,
    parameter logic [15:0] VEHICLE_ID = 16'h0017,
    parameter int LED_HOLD_CYCLES = 50_000_000
)(
    input logic clk, input logic rst,
    input logic emergency_button, input logic accept_button, input logic clear_button,
    input logic [7:0] event_id,
    input logic uart_rx, output logic uart_tx,
    output logic [15:0] debug_vehicle_id,
    output logic [7:0] debug_event_display,
    output logic led_emergency, output logic led_packet, output logic led_tx,
    output logic led_done, output logic led_rx, output logic led_ack
);
    localparam logic [7:0] TYPE_ACK = 8'hF0;

    logic send_pulse, accept_pulse, clear_pulse;
    button_pulse u_b1(.clk(clk),.rst(rst),.button_in(emergency_button),.pulse(send_pulse));
    button_pulse u_b2(.clk(clk),.rst(rst),.button_in(accept_button),.pulse(accept_pulse));
    button_pulse u_b3(.clk(clk),.rst(rst),.button_in(clear_button),.pulse(clear_pulse));

    logic [7:0] rx_byte; logic rx_valid;
    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_rx(
        .clk(clk),.rst(rst),.rxd(uart_rx),.data_out(rx_byte),.data_valid(rx_valid));

    logic [47:0] rx_packet; logic rx_packet_valid;
    logic [7:0] rx_event; logic [15:0] rx_vehicle; logic frame_error;
    packet_decoder u_dec(
        .clk(clk),.rst(rst),.byte_in(rx_byte),.byte_valid(rx_valid),
        .packet_out(rx_packet),.packet_valid(rx_packet_valid),
        .event_id(rx_event),.vehicle_id(rx_vehicle),.frame_error(frame_error));

    logic crc_pass, crc_done;
    crc_checker u_chk(
        .clk(clk),.rst(rst),.packet_in(rx_packet),
        .packet_valid(rx_packet_valid),.crc_pass(crc_pass),.crc_done(crc_done));

    logic [15:0] received_vehicle_latched;
    logic [7:0] received_event_latched;
    logic received_valid;
    always_ff @(posedge clk) begin
        if(rst || clear_pulse) begin
            received_vehicle_latched<=16'h0000;
            received_event_latched<=8'h00;
            received_valid<=1'b0;
        end else if(rx_packet_valid && crc_pass && rx_event!=TYPE_ACK) begin
            received_vehicle_latched<=rx_vehicle;
            received_event_latched<=rx_event;
            received_valid<=1'b1;
        end
    end

    logic tx_request; logic [7:0] tx_event;
    logic uart_start, uart_busy, uart_done; logic [7:0] uart_data;
    logic packet_done, packet_busy; logic [47:0] tx_packet;

    always_comb begin
        tx_request=1'b0; tx_event=event_id;
        if(!packet_busy) begin
            if(send_pulse) begin tx_request=1'b1; tx_event=event_id; end
            else if(accept_pulse && received_valid) begin tx_request=1'b1; tx_event=TYPE_ACK; end
        end
    end

    packet_generator u_pkt(
        .clk(clk),.rst(rst),.request(tx_request),.event_id(tx_event),
        .vehicle_id(VEHICLE_ID),.uart_start(uart_start),.uart_data(uart_data),
        .uart_busy(uart_busy),.uart_done(uart_done),.busy(packet_busy),
        .packet_done(packet_done),.packet_out(tx_packet));

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BAUD_RATE(BAUD_RATE)) u_tx(
        .clk(clk),.rst(rst),.tx_start(uart_start),.tx_data(uart_data),
        .tx(uart_tx),.tx_busy(uart_busy),.tx_done(uart_done));

    assign debug_vehicle_id = received_valid ? received_vehicle_latched : VEHICLE_ID;

    localparam int CW=(LED_HOLD_CYCLES<=1)?1:$clog2(LED_HOLD_CYCLES+1);
    logic [CW-1:0] em_cnt,pk_cnt,rx_cnt,ack_cnt,done_cnt;
    always_ff @(posedge clk) begin
        if(rst || clear_pulse) begin
            em_cnt<='0; pk_cnt<='0; rx_cnt<='0; ack_cnt<='0; done_cnt<='0;
        end else begin
            if(send_pulse) em_cnt<=LED_HOLD_CYCLES;
            else if(em_cnt!=0) em_cnt<=em_cnt-1'b1;
            if(packet_done) begin pk_cnt<=LED_HOLD_CYCLES; done_cnt<=LED_HOLD_CYCLES; end
            else begin
                if(pk_cnt!=0) pk_cnt<=pk_cnt-1'b1;
                if(done_cnt!=0) done_cnt<=done_cnt-1'b1;
            end
            if(rx_packet_valid && crc_pass) rx_cnt<=LED_HOLD_CYCLES;
            else if(rx_cnt!=0) rx_cnt<=rx_cnt-1'b1;
            if(rx_packet_valid && crc_pass && rx_event==TYPE_ACK) ack_cnt<=LED_HOLD_CYCLES;
            else if(ack_cnt!=0) ack_cnt<=ack_cnt-1'b1;
        end
    end

    assign led_emergency=(em_cnt!=0);
    assign led_packet=(pk_cnt!=0);
    assign led_done=(done_cnt!=0);
    assign led_rx=(rx_cnt!=0);
    assign led_ack=(ack_cnt!=0);
    assign led_tx=uart_busy;

    always_comb begin
        debug_event_display[7]=(crc_done && !crc_pass)?1'b0:1'b1;
        case(received_valid?received_event_latched:event_id)
            8'h00: debug_event_display[6:0]=7'b1000000;
            8'h01: debug_event_display[6:0]=7'b1111001;
            8'h02: debug_event_display[6:0]=7'b0100100;
            8'h03: debug_event_display[6:0]=7'b0110000;
            8'h04: debug_event_display[6:0]=7'b0011001;
            8'h05: debug_event_display[6:0]=7'b0010010;
            8'h06: debug_event_display[6:0]=7'b0000010;
            8'h07: debug_event_display[6:0]=7'b1111000;
            8'h08: debug_event_display[6:0]=7'b0000000;
            8'h09: debug_event_display[6:0]=7'b0010000;
            8'h0A: debug_event_display[6:0]=7'b0001000;
            8'h0B: debug_event_display[6:0]=7'b0000011;
            8'h0C: debug_event_display[6:0]=7'b1000110;
            8'h0D: debug_event_display[6:0]=7'b0100001;
            8'h0E: debug_event_display[6:0]=7'b0000110;
            8'h0F: debug_event_display[6:0]=7'b0001110;
            8'hF0: debug_event_display[6:0]=7'b0000110;
            default: debug_event_display[6:0]=7'b1111111;
        endcase
    end
endmodule
