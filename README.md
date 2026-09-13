# SAFE-Link NodeMCU bridge

## Architecture
FPGA #1 <-> UART <-> NodeMCU #1 )) Wi-Fi/TCP (( NodeMCU #2 <-> UART <-> FPGA #2

Both directions work. The NodeMCUs are transparent transport bridges; FPGA packet generation and CRC stay unchanged.

## Exact wiring (both sides)
FPGA U11 (uart_tx) ---> NodeMCU D7 / GPIO13 (RX)
FPGA V12 (uart_rx) <--- NodeMCU D8 / GPIO15 (TX)
FPGA GND ------------ NodeMCU GND

Cross TX/RX. Do not connect TX-to-TX. Use 3.3 V logic only.

## NodeMCU roles
NodeMCU #1 = Access Point, IP 192.168.4.1, TCP server port 5000.
SSID = SAFE-LINK
Password = SafeLink123

NodeMCU #2 = Station/client; it joins SAFE-LINK and connects to 192.168.4.1:5000.

## Programming NodeMCU
Arduino IDE -> install ESP8266 board package -> select "NodeMCU 1.0 (ESP-12E Module)".
Upload NodeMCU_1_AP_Server.ino to board #1.
Upload NodeMCU_2_Client.ino to board #2.
After boot, Serial.swap() moves hardware UART to D8 TX / D7 RX. Do not use Serial Monitor as a bridge monitor after the swap.

## FPGA
Create a Vivado project for XC7S50-CSGA324-1.
Add every .sv file in FPGA/src and FPGA/constraints/common.xdc.
Top module: roadsos_top.

Build/program FPGA #1 with VEHICLE_ID=16'h0017 and FPGA #2 with VEHICLE_ID=16'h0018.
If your Vivado flow cannot set parameters from the GUI, edit the default VEHICLE_ID in roadsos_top_bridge.sv before building each bitstream.

## Reused from your previous ZIP
button_pulse.sv
crc_checker.sv
crc_generator.sv
packet_decoder.sv
packet_generator.sv
uart_rx.sv
uart_tx.sv
common.xdc

These are included unchanged so the package is self-contained.

## Test sequence
1. Power/program both NodeMCUs.
2. Program both FPGAs.
3. Wire UART and GND exactly as above.
4. Wait for NodeMCU #2 to join SAFE-LINK.
5. Release FPGA reset.
6. Set SW0..SW7 to event 01.
7. Press J5 on FPGA #1.
8. FPGA #2 should show vehicle ID 0017 on LD0..LD15 and event 1 on the 7-segment; RGB0 BLUE indicates valid reception.
9. Repeat in reverse from FPGA #2.

## Packet
A5 | EVENT | VEH_H | VEH_L | CRC_H | CRC_L | 5A | 0A

CRC is CRC-16/CCITT-FALSE over A5, EVENT, VEH_H, VEH_L. NodeMCUs do not alter the bytes.

## Debug order
If it fails:
1. Check FPGA TX indicator.
2. Check NodeMCU #1 is powered and creating SAFE-LINK.
3. Check NodeMCU #2 connects.
4. Check U11 -> D7, V12 <- D8, GND -> GND.
5. Check both UARTs are 115200 8N1.
6. Test one direction first.
7. Only after basic packet reception works, test ACK.

## Engineering note
This is a Wi-Fi/TCP prototype, not LoRa. It validates the FPGA communication unit and packet/CRC layer. Later, the transport bridge can be replaced by a LoRa gateway while keeping the FPGA packet format.
