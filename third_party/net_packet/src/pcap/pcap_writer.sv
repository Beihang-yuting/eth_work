// src/pcap/pcap_writer.sv
`ifndef PCAP_WRITER_SV
`define PCAP_WRITER_SV

`include "core/packet.sv"

class pcap_writer;

    int fd;
    string filename;

    function void open(string path);
        filename = path;
        fd = $fopen(path, "wb");
        if (fd == 0) begin
            $warning("pcap_writer::open: cannot open file %s", path);
            return;
        end
        write_global_header();
    endfunction

    function void write_global_header();
        // Magic number (big-endian pcap)
        write_32(32'hA1B2C3D4);
        // Version 2.4
        write_16(16'd2);
        write_16(16'd4);
        // Timezone, sigfigs
        write_32(32'd0);
        write_32(32'd0);
        // Snaplen
        write_32(32'd65535);
        // Network (Ethernet)
        write_32(32'd1);
    endfunction

    function void write_packet(packet pkt, int unsigned timestamp_sec = 0,
                                int unsigned timestamp_usec = 0);
        int unsigned pkt_len;

        if (fd == 0) return;

        // Ensure packet has raw_data
        if (pkt.raw_data.size() == 0) begin
            pkt.do_pack();
        end

        pkt_len = pkt.raw_data.size();

        // Packet header
        write_32(timestamp_sec);
        write_32(timestamp_usec);
        write_32(pkt_len);   // incl_len
        write_32(pkt_len);   // orig_len

        // Packet data
        foreach (pkt.raw_data[i])
            $fwrite(fd, "%c", pkt.raw_data[i]);
    endfunction

    function void write_packets(packet pkts[$]);
        foreach (pkts[i])
            write_packet(pkts[i], i, 0);
    endfunction

    function void close();
        if (fd != 0) begin
            $fclose(fd);
            fd = 0;
        end
    endfunction

    // --- Internal helpers ---
    protected function void write_32(bit [31:0] val);
        // Big-endian write
        $fwrite(fd, "%c%c%c%c", val[31:24], val[23:16], val[15:8], val[7:0]);
    endfunction

    protected function void write_16(bit [15:0] val);
        $fwrite(fd, "%c%c", val[15:8], val[7:0]);
    endfunction

endclass

`endif // PCAP_WRITER_SV
