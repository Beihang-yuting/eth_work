// src/pcap/pcap_reader.sv
`ifndef PCAP_READER_SV
`define PCAP_READER_SV

`include "core/packet.sv"

class pcap_reader;

    int fd;
    string filename;
    bit is_big_endian;
    bit at_eof;

    function void open(string path);
        int unsigned magic;
        filename = path;
        at_eof = 0;
        fd = $fopen(path, "rb");
        if (fd == 0) begin
            $warning("pcap_reader::open: cannot open file %s", path);
            at_eof = 1;
            return;
        end
        // Read global header
        magic = read_32_raw();
        if (magic == 32'hA1B2C3D4) begin
            is_big_endian = 1;
        end else if (magic == 32'hD4C3B2A1) begin
            is_big_endian = 0;
        end else begin
            $warning("pcap_reader::open: invalid magic number 0x%08x", magic);
            $fclose(fd);
            fd = 0;
            at_eof = 1;
            return;
        end
        // Skip rest of global header (20 bytes: version, timezone, sigfigs, snaplen, network)
        begin
            int c;
            for (int i = 0; i < 20; i++) begin
                c = $fgetc(fd);
                if (c == -1) begin at_eof = 1; return; end
            end
        end
    endfunction

    function packet read_next();
        int unsigned ts_sec, ts_usec, incl_len, orig_len;
        byte unsigned data[$];
        packet pkt;

        if (fd == 0 || at_eof) return null;

        // Read packet header (16 bytes)
        ts_sec   = read_32();
        ts_usec  = read_32();
        incl_len = read_32();
        orig_len = read_32();

        if (at_eof) return null;

        // Read packet data
        for (int i = 0; i < int'(incl_len); i++) begin
            int c = $fgetc(fd);
            if (c == -1) begin at_eof = 1; return null; end
            data.push_back(c[7:0]);
        end

        // Parse
        pkt = new();
        pkt.unpack(data);
        return pkt;
    endfunction

    function void read_all(ref packet pkts[$]);
        pkts.delete();
        while (!eof()) begin
            packet pkt = read_next();
            if (pkt != null)
                pkts.push_back(pkt);
        end
    endfunction

    function bit eof();
        return at_eof || (fd == 0);
    endfunction

    function void close();
        if (fd != 0) begin
            $fclose(fd);
            fd = 0;
        end
        at_eof = 1;
    endfunction

    // --- Internal helpers ---
    protected function int unsigned read_32_raw();
        // Always big-endian raw read (for magic number detection)
        int b0, b1, b2, b3;
        b0 = $fgetc(fd); if (b0 == -1) begin at_eof = 1; return 0; end
        b1 = $fgetc(fd); if (b1 == -1) begin at_eof = 1; return 0; end
        b2 = $fgetc(fd); if (b2 == -1) begin at_eof = 1; return 0; end
        b3 = $fgetc(fd); if (b3 == -1) begin at_eof = 1; return 0; end
        return {b0[7:0], b1[7:0], b2[7:0], b3[7:0]};
    endfunction

    protected function int unsigned read_32();
        int b0, b1, b2, b3;
        b0 = $fgetc(fd); if (b0 == -1) begin at_eof = 1; return 0; end
        b1 = $fgetc(fd); if (b1 == -1) begin at_eof = 1; return 0; end
        b2 = $fgetc(fd); if (b2 == -1) begin at_eof = 1; return 0; end
        b3 = $fgetc(fd); if (b3 == -1) begin at_eof = 1; return 0; end
        if (is_big_endian)
            return {b0[7:0], b1[7:0], b2[7:0], b3[7:0]};
        else
            return {b3[7:0], b2[7:0], b1[7:0], b0[7:0]};
    endfunction

endclass

`endif // PCAP_READER_SV
