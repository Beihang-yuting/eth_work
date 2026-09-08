// src/protocols/rdma/rocev2_header.sv
`ifndef ROCEV2_HEADER_SV
`define ROCEV2_HEADER_SV

`include "protocol_base.sv"

// IB Spec Chapter 9 — Complete RoCEv2 Opcode Enumeration
// Transport types: RC (0x00-0x1F), UC (0x20-0x3F), RD (0x40-0x5F), UD (0x60-0x7F), CNP (0x80-0x81)
typedef enum bit [7:0] {
    // RC - Reliable Connection
    RC_SEND_FIRST               = 8'h00,
    RC_SEND_MIDDLE              = 8'h01,
    RC_SEND_LAST                = 8'h02,
    RC_SEND_LAST_IMM            = 8'h03,
    RC_SEND_ONLY                = 8'h04,
    RC_SEND_ONLY_IMM            = 8'h05,
    RC_RDMA_WRITE_FIRST         = 8'h06,
    RC_RDMA_WRITE_MIDDLE        = 8'h07,
    RC_RDMA_WRITE_LAST          = 8'h08,
    RC_RDMA_WRITE_LAST_IMM      = 8'h09,
    RC_RDMA_WRITE_ONLY          = 8'h0A,
    RC_RDMA_WRITE_ONLY_IMM      = 8'h0B,
    RC_RDMA_READ_REQ            = 8'h0C,
    RC_RDMA_READ_RESP_FIRST     = 8'h0D,
    RC_RDMA_READ_RESP_MIDDLE    = 8'h0E,
    RC_RDMA_READ_RESP_LAST      = 8'h0F,
    RC_RDMA_READ_RESP_ONLY      = 8'h10,
    RC_ACK                      = 8'h11,
    RC_ATOMIC_ACK               = 8'h12,
    RC_CMP_SWAP                 = 8'h13,
    RC_FETCH_ADD                = 8'h14,
    RC_SEND_LAST_INV            = 8'h16,
    RC_SEND_ONLY_INV            = 8'h17,
    // UC - Unreliable Connection
    UC_SEND_FIRST               = 8'h20,
    UC_SEND_MIDDLE              = 8'h21,
    UC_SEND_LAST                = 8'h22,
    UC_SEND_LAST_IMM            = 8'h23,
    UC_SEND_ONLY                = 8'h24,
    UC_SEND_ONLY_IMM            = 8'h25,
    UC_RDMA_WRITE_FIRST         = 8'h26,
    UC_RDMA_WRITE_MIDDLE        = 8'h27,
    UC_RDMA_WRITE_LAST          = 8'h28,
    UC_RDMA_WRITE_LAST_IMM      = 8'h29,
    UC_RDMA_WRITE_ONLY          = 8'h2A,
    UC_RDMA_WRITE_ONLY_IMM      = 8'h2B,
    // UD - Unreliable Datagram
    UD_SEND_ONLY                = 8'h64,
    UD_SEND_ONLY_IMM            = 8'h65,
    // CNP
    RC_CNP                      = 8'h81
} rocev2_opcode_e;

// ============================================================================
// IB Spec Chapter 9 — Opcode to Extended Header Mapping (Table 38)
// ============================================================================
//
// Transport Types:
//   RC (0x00-0x1F) : Reliable Connection — most common, supports all operations
//   UC (0x20-0x3F) : Unreliable Connection — no ACK, Write/Send only
//   UD (0x60-0x7F) : Unreliable Datagram — connectionless, requires DETH
//   CNP (0x81)     : Congestion Notification Packet
//
// Extended Transport Headers:
//   RETH (16B)         : VA(64) + R_Key(32) + DMA_Length(32) — for RDMA Write/Read
//   AETH (4B)          : Syndrome(8) + MSN(24) — for ACK/ReadResponse
//   AtomicETH (28B)    : VA(64) + R_Key(32) + SwapAdd(64) + Compare(64) — for CmpSwap/FetchAdd
//   AtomicAckETH (8B)  : OrigRemoteData(64) — for Atomic ACK response
//   ImmDt (4B)         : ImmediateData(32) — inline data notification
//   IETH (4B)          : R_Key_to_Invalidate(32) — memory region invalidation
//   DETH (8B)          : Q_Key(32) + SrcQP(24) + Rsvd(8) — for UD mode
//   ICRC (4B)          : Invariant CRC — mandatory trailer on all RoCEv2 packets
//
// +---------------------------------+-----+------+------+-----------+--------------+------+-------+------+-------+
// | Opcode                          | BTH | RETH | AETH | AtomicETH | AtomicAckETH | DETH | ImmDt | IETH | Bytes |
// +---------------------------------+-----+------+------+-----------+--------------+------+-------+------+-------+
// | RC_SEND_FIRST          (0x00)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_SEND_MIDDLE         (0x01)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_SEND_LAST           (0x02)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_SEND_LAST_IMM       (0x03)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | RC_SEND_ONLY           (0x04)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_SEND_ONLY_IMM       (0x05)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | RC_RDMA_WRITE_FIRST    (0x06)   |  v  |  v   |      |           |              |      |       |      |  32   |
// | RC_RDMA_WRITE_MIDDLE   (0x07)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_RDMA_WRITE_LAST     (0x08)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_RDMA_WRITE_LAST_IMM (0x09)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | RC_RDMA_WRITE_ONLY     (0x0A)   |  v  |  v   |      |           |              |      |       |      |  32   |
// | RC_RDMA_WRITE_ONLY_IMM (0x0B)   |  v  |  v   |      |           |              |      |   v   |      |  36   |
// | RC_RDMA_READ_REQ       (0x0C)   |  v  |  v   |      |           |              |      |       |      |  32   |
// | RC_RDMA_READ_RESP_FIRST(0x0D)   |  v  |      |  v   |           |              |      |       |      |  20   |
// | RC_RDMA_READ_RESP_MID  (0x0E)   |  v  |      |      |           |              |      |       |      |  16   |
// | RC_RDMA_READ_RESP_LAST (0x0F)   |  v  |      |  v   |           |              |      |       |      |  20   |
// | RC_RDMA_READ_RESP_ONLY (0x10)   |  v  |      |  v   |           |              |      |       |      |  20   |
// | RC_ACK                 (0x11)   |  v  |      |  v   |           |              |      |       |      |  20   |
// | RC_ATOMIC_ACK          (0x12)   |  v  |      |  v   |           |      v       |      |       |      |  28   |
// | RC_CMP_SWAP            (0x13)   |  v  |      |      |     v     |              |      |       |      |  44   |
// | RC_FETCH_ADD           (0x14)   |  v  |      |      |     v     |              |      |       |      |  44   |
// | RC_SEND_LAST_INV       (0x16)   |  v  |      |      |           |              |      |       |  v   |  20   |
// | RC_SEND_ONLY_INV       (0x17)   |  v  |      |      |           |              |      |       |  v   |  20   |
// | UC_SEND_FIRST          (0x20)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_SEND_MIDDLE         (0x21)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_SEND_LAST           (0x22)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_SEND_LAST_IMM       (0x23)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | UC_SEND_ONLY           (0x24)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_SEND_ONLY_IMM       (0x25)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | UC_RDMA_WRITE_FIRST    (0x26)   |  v  |  v   |      |           |              |      |       |      |  32   |
// | UC_RDMA_WRITE_MIDDLE   (0x27)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_RDMA_WRITE_LAST     (0x28)   |  v  |      |      |           |              |      |       |      |  16   |
// | UC_RDMA_WRITE_LAST_IMM (0x29)   |  v  |      |      |           |              |      |   v   |      |  20   |
// | UC_RDMA_WRITE_ONLY     (0x2A)   |  v  |  v   |      |           |              |      |       |      |  32   |
// | UC_RDMA_WRITE_ONLY_IMM (0x2B)   |  v  |  v   |      |           |              |      |   v   |      |  36   |
// | UD_SEND_ONLY           (0x64)   |  v  |      |      |           |              |  v   |       |      |  24   |
// | UD_SEND_ONLY_IMM       (0x65)   |  v  |      |      |           |              |  v   |   v   |      |  28   |
// | RC_CNP                 (0x81)   |  v  |      |      |           |              |      |       |      |  16   |
// +---------------------------------+-----+------+------+-----------+--------------+------+-------+------+-------+
// Bytes column = BTH(12) + extensions + ICRC(4), excludes payload
//

class rocev2_bth extends protocol_base;

    // === BTH fields (12 bytes) ===
    rand rocev2_opcode_e opcode;
    rand bit        se;
    rand bit        mig_req;
    rand bit [1:0]  pad_count;
    rand bit [3:0]  tver;
    rand bit [15:0] pkey;
    rand bit [23:0] dest_qp;
    rand bit        ack_req;
    rand bit [6:0]  reserved1;
    rand bit [23:0] psn;
    rand bit [7:0]  reserved2;

    // === RETH fields (16 bytes, conditional) ===
    rand bit [63:0] reth_va;
    rand bit [31:0] reth_r_key;
    rand bit [31:0] reth_dma_len;

    // === AETH fields (4 bytes, conditional) ===
    rand bit [7:0]  aeth_syndrome;
    rand bit [23:0] aeth_msn;

    // === ImmDt fields (4 bytes, conditional) ===
    rand bit [31:0] imm_data;

    // === AtomicETH fields (28 bytes, for CmpSwap/FetchAdd) ===
    rand bit [63:0] atomic_va;
    rand bit [31:0] atomic_r_key;
    rand bit [63:0] atomic_swap_add;   // Swap data (CmpSwap) or Add data (FetchAdd)
    rand bit [63:0] atomic_compare;    // Compare data (CmpSwap only, FetchAdd sets to 0)

    // === AtomicAckETH fields (8 bytes, for Atomic ACK) ===
    rand bit [63:0] atomic_orig_data;

    // === IETH fields (4 bytes, for Send/Write with Invalidate) ===
    rand bit [31:0] ieth_r_key;

    // === DETH fields (8 bytes, for UD operations) ===
    rand bit [31:0] deth_q_key;
    rand bit [23:0] deth_src_qp;
    rand bit [7:0]  deth_reserved;

    // === ICRC (4 bytes, trailer) ===
    bit             icrc_enable;
    bit [31:0]      icrc;

    constraint c_default {
        soft opcode    == RC_SEND_ONLY;
        soft tver      == 4'd0;
        soft reserved1 == 0;
        soft reserved2 == 0;
        soft pad_count == 0;
        soft se        == 0;
        soft mig_req   == 0;
        soft deth_reserved == 0;
    }

    function new();
        proto_type       = PROTO_ROCEV2;
        opcode           = RC_SEND_ONLY;
        se               = 0;
        mig_req          = 0;
        pad_count        = 0;
        tver             = 0;
        pkey             = 16'hFFFF;
        dest_qp          = 0;
        ack_req          = 0;
        reserved1        = 0;
        psn              = 0;
        reserved2        = 0;
        reth_va          = 0;
        reth_r_key       = 0;
        reth_dma_len     = 0;
        aeth_syndrome    = 0;
        aeth_msn         = 0;
        imm_data         = 0;
        atomic_va        = 0;
        atomic_r_key     = 0;
        atomic_swap_add  = 0;
        atomic_compare   = 0;
        atomic_orig_data = 0;
        ieth_r_key       = 0;
        deth_q_key       = 0;
        deth_src_qp      = 0;
        deth_reserved    = 0;
        icrc_enable      = 1;
        icrc             = 0;
    endfunction

    static function rocev2_bth create(rocev2_opcode_e op = RC_SEND_ONLY, bit [23:0] qp = 0);
        rocev2_bth h = new();
        h.opcode  = op;
        h.dest_qp = qp;
        return h;
    endfunction

    // --- Opcode classification helpers (IB Spec Table 38) ---

    function bit has_reth();
        return (opcode inside {RC_RDMA_WRITE_FIRST, RC_RDMA_WRITE_ONLY, RC_RDMA_WRITE_ONLY_IMM,
                               RC_RDMA_READ_REQ,
                               UC_RDMA_WRITE_FIRST, UC_RDMA_WRITE_ONLY, UC_RDMA_WRITE_ONLY_IMM});
    endfunction

    function bit has_aeth();
        return (opcode inside {RC_RDMA_READ_RESP_FIRST, RC_RDMA_READ_RESP_LAST,
                               RC_RDMA_READ_RESP_ONLY, RC_ACK, RC_ATOMIC_ACK});
    endfunction

    function bit has_immdt();
        return (opcode inside {RC_SEND_LAST_IMM, RC_SEND_ONLY_IMM,
                               RC_RDMA_WRITE_LAST_IMM, RC_RDMA_WRITE_ONLY_IMM,
                               UC_SEND_LAST_IMM, UC_SEND_ONLY_IMM,
                               UC_RDMA_WRITE_LAST_IMM, UC_RDMA_WRITE_ONLY_IMM,
                               UD_SEND_ONLY_IMM});
    endfunction

    function bit has_atomic_eth();
        return (opcode inside {RC_CMP_SWAP, RC_FETCH_ADD});
    endfunction

    function bit has_atomic_ack_eth();
        return (opcode == RC_ATOMIC_ACK);
    endfunction

    function bit has_ieth();
        return (opcode inside {RC_SEND_LAST_INV, RC_SEND_ONLY_INV});
    endfunction

    function bit has_deth();
        return (opcode inside {UD_SEND_ONLY, UD_SEND_ONLY_IMM});
    endfunction

    virtual function void pack_header(ref byte unsigned data[$]);
        // BTH (12 bytes)
        bit [31:0] word0 = {opcode, se, mig_req, pad_count, tver, pkey};
        bit [31:0] word1 = {dest_qp, ack_req, reserved1};
        bit [31:0] word2 = {psn, reserved2};
        bit [31:0] tmp32;
        packet_utils::pack_bytes_32(data, word0);
        packet_utils::pack_bytes_32(data, word1);
        packet_utils::pack_bytes_32(data, word2);

        // RETH (16 bytes)
        if (has_reth()) begin
            tmp32 = reth_va[63:32]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = reth_va[31:0]; packet_utils::pack_bytes_32(data, tmp32);
            packet_utils::pack_bytes_32(data, reth_r_key);
            packet_utils::pack_bytes_32(data, reth_dma_len);
        end

        // AETH (4 bytes)
        if (has_aeth()) begin
            tmp32 = {aeth_syndrome, aeth_msn}; packet_utils::pack_bytes_32(data, tmp32);
        end

        // AtomicETH (28 bytes)
        if (has_atomic_eth()) begin
            tmp32 = atomic_va[63:32]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = atomic_va[31:0]; packet_utils::pack_bytes_32(data, tmp32);
            packet_utils::pack_bytes_32(data, atomic_r_key);
            tmp32 = atomic_swap_add[63:32]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = atomic_swap_add[31:0]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = atomic_compare[63:32]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = atomic_compare[31:0]; packet_utils::pack_bytes_32(data, tmp32);
        end

        // AtomicAckETH (8 bytes)
        if (has_atomic_ack_eth()) begin
            tmp32 = atomic_orig_data[63:32]; packet_utils::pack_bytes_32(data, tmp32);
            tmp32 = atomic_orig_data[31:0]; packet_utils::pack_bytes_32(data, tmp32);
        end

        // DETH (8 bytes)
        if (has_deth()) begin
            packet_utils::pack_bytes_32(data, deth_q_key);
            begin
                bit [31:0] _tmp = {deth_src_qp, deth_reserved};
                packet_utils::pack_bytes_32(data, _tmp);
            end
        end

        // ImmDt (4 bytes)
        if (has_immdt()) begin
            packet_utils::pack_bytes_32(data, imm_data);
        end

        // IETH (4 bytes)
        if (has_ieth()) begin
            packet_utils::pack_bytes_32(data, ieth_r_key);
        end

        // ICRC (4 bytes)
        if (icrc_enable) begin
            packet_utils::pack_bytes_32(data, icrc);
        end
    endfunction

    virtual function void unpack_header(ref byte unsigned data[$], ref int offset);
        bit [31:0] word0, word1, word2;
        // BTH
        word0 = packet_utils::unpack_bytes_32(data, offset);
        word1 = packet_utils::unpack_bytes_32(data, offset);
        word2 = packet_utils::unpack_bytes_32(data, offset);
        opcode    = rocev2_opcode_e'(word0[31:24]);
        se        = word0[23];
        mig_req   = word0[22];
        pad_count = word0[21:20];
        tver      = word0[19:16];
        pkey      = word0[15:0];
        dest_qp   = word1[31:8];
        ack_req   = word1[7];
        reserved1 = word1[6:0];
        psn       = word2[31:8];
        reserved2 = word2[7:0];

        // RETH (opcode already parsed, has_reth works)
        if (has_reth()) begin
            reth_va[63:32] = packet_utils::unpack_bytes_32(data, offset);
            reth_va[31:0]  = packet_utils::unpack_bytes_32(data, offset);
            reth_r_key     = packet_utils::unpack_bytes_32(data, offset);
            reth_dma_len   = packet_utils::unpack_bytes_32(data, offset);
        end

        // AETH
        if (has_aeth()) begin
            bit [31:0] aeth_word = packet_utils::unpack_bytes_32(data, offset);
            aeth_syndrome = aeth_word[31:24];
            aeth_msn      = aeth_word[23:0];
        end

        // AtomicETH
        if (has_atomic_eth()) begin
            atomic_va[63:32]       = packet_utils::unpack_bytes_32(data, offset);
            atomic_va[31:0]        = packet_utils::unpack_bytes_32(data, offset);
            atomic_r_key           = packet_utils::unpack_bytes_32(data, offset);
            atomic_swap_add[63:32] = packet_utils::unpack_bytes_32(data, offset);
            atomic_swap_add[31:0]  = packet_utils::unpack_bytes_32(data, offset);
            atomic_compare[63:32]  = packet_utils::unpack_bytes_32(data, offset);
            atomic_compare[31:0]   = packet_utils::unpack_bytes_32(data, offset);
        end

        // AtomicAckETH
        if (has_atomic_ack_eth()) begin
            atomic_orig_data[63:32] = packet_utils::unpack_bytes_32(data, offset);
            atomic_orig_data[31:0]  = packet_utils::unpack_bytes_32(data, offset);
        end

        // DETH
        if (has_deth()) begin
            bit [31:0] deth_word1;
            deth_q_key    = packet_utils::unpack_bytes_32(data, offset);
            deth_word1    = packet_utils::unpack_bytes_32(data, offset);
            deth_src_qp   = deth_word1[31:8];
            deth_reserved = deth_word1[7:0];
        end

        // ImmDt
        if (has_immdt()) begin
            imm_data = packet_utils::unpack_bytes_32(data, offset);
        end

        // IETH
        if (has_ieth()) begin
            ieth_r_key = packet_utils::unpack_bytes_32(data, offset);
        end

        // ICRC
        if (icrc_enable) begin
            icrc = packet_utils::unpack_bytes_32(data, offset);
        end
    endfunction

    virtual function int get_header_length();
        int len = 12;  // BTH always
        if (has_reth())           len += 16;
        if (has_aeth())           len += 4;
        if (has_atomic_eth())     len += 28;
        if (has_atomic_ack_eth()) len += 8;
        if (has_deth())           len += 8;
        if (has_immdt())          len += 4;
        if (has_ieth())           len += 4;
        if (icrc_enable)          len += 4;
        return len;
    endfunction

    virtual function void calc_fields(byte unsigned payload_data[$], protocol_type_e next_proto);
        if (!auto_calc) return;
        tver = 0;
        // Simple ICRC placeholder
        if (icrc_enable) begin
            byte unsigned icrc_data[$];
            bit saved = icrc_enable;
            icrc_enable = 0;
            pack_header(icrc_data);
            icrc_enable = saved;
            foreach (payload_data[i]) icrc_data.push_back(payload_data[i]);
            icrc = 32'h0;
            foreach (icrc_data[i])
                icrc = icrc ^ ({24'h0, icrc_data[i]} << ((i % 4) * 8));
        end
    endfunction

    virtual function protocol_base clone();
        rocev2_bth h = new();
        h.opcode           = opcode;
        h.se               = se;
        h.mig_req          = mig_req;
        h.pad_count        = pad_count;
        h.tver             = tver;
        h.pkey             = pkey;
        h.dest_qp          = dest_qp;
        h.ack_req          = ack_req;
        h.reserved1        = reserved1;
        h.psn              = psn;
        h.reserved2        = reserved2;
        h.reth_va          = reth_va;
        h.reth_r_key       = reth_r_key;
        h.reth_dma_len     = reth_dma_len;
        h.aeth_syndrome    = aeth_syndrome;
        h.aeth_msn         = aeth_msn;
        h.imm_data         = imm_data;
        h.atomic_va        = atomic_va;
        h.atomic_r_key     = atomic_r_key;
        h.atomic_swap_add  = atomic_swap_add;
        h.atomic_compare   = atomic_compare;
        h.atomic_orig_data = atomic_orig_data;
        h.ieth_r_key       = ieth_r_key;
        h.deth_q_key       = deth_q_key;
        h.deth_src_qp      = deth_src_qp;
        h.deth_reserved    = deth_reserved;
        h.icrc_enable      = icrc_enable;
        h.icrc             = icrc;
        h.auto_calc        = auto_calc;
        return h;
    endfunction

    virtual function bit compare(protocol_base other);
        rocev2_bth o;
        if (!$cast(o, other)) return 0;
        if (opcode != o.opcode || pkey != o.pkey) return 0;
        if (dest_qp != o.dest_qp || psn != o.psn) return 0;
        if (has_reth())
            if (reth_va != o.reth_va || reth_r_key != o.reth_r_key || reth_dma_len != o.reth_dma_len) return 0;
        if (has_aeth())
            if (aeth_syndrome != o.aeth_syndrome || aeth_msn != o.aeth_msn) return 0;
        if (has_immdt())
            if (imm_data != o.imm_data) return 0;
        if (has_atomic_eth())
            if (atomic_va != o.atomic_va || atomic_r_key != o.atomic_r_key ||
                atomic_swap_add != o.atomic_swap_add || atomic_compare != o.atomic_compare) return 0;
        if (has_atomic_ack_eth())
            if (atomic_orig_data != o.atomic_orig_data) return 0;
        if (has_ieth())
            if (ieth_r_key != o.ieth_r_key) return 0;
        if (has_deth())
            if (deth_q_key != o.deth_q_key || deth_src_qp != o.deth_src_qp) return 0;
        return 1;
    endfunction

    virtual function string to_string();
        string s;
        s = $sformatf("=== %s (BTH) ===\n", proto_type.name());
        s = {s, $sformatf("  opcode   : %s (0x%02x)\n", opcode.name(), opcode)};
        s = {s, $sformatf("  se       : %0b\n", se)};
        s = {s, $sformatf("  mig_req  : %0b\n", mig_req)};
        s = {s, $sformatf("  pad_count: %0d\n", pad_count)};
        s = {s, $sformatf("  tver     : %0d\n", tver)};
        s = {s, $sformatf("  pkey     : 0x%04x\n", pkey)};
        s = {s, $sformatf("  dest_qp  : 0x%06x\n", dest_qp)};
        s = {s, $sformatf("  ack_req  : %0b\n", ack_req)};
        s = {s, $sformatf("  psn      : 0x%06x\n", psn)};
        if (has_reth()) begin
            s = {s, "  --- RETH ---\n"};
            s = {s, $sformatf("  va       : 0x%016x\n", reth_va)};
            s = {s, $sformatf("  r_key    : 0x%08x\n", reth_r_key)};
            s = {s, $sformatf("  dma_len  : %0d\n", reth_dma_len)};
        end
        if (has_aeth()) begin
            s = {s, "  --- AETH ---\n"};
            s = {s, $sformatf("  syndrome : 0x%02x\n", aeth_syndrome)};
            s = {s, $sformatf("  msn      : 0x%06x\n", aeth_msn)};
        end
        if (has_atomic_eth()) begin
            s = {s, "  --- AtomicETH ---\n"};
            s = {s, $sformatf("  va       : 0x%016x\n", atomic_va)};
            s = {s, $sformatf("  r_key    : 0x%08x\n", atomic_r_key)};
            s = {s, $sformatf("  swap_add : 0x%016x\n", atomic_swap_add)};
            s = {s, $sformatf("  compare  : 0x%016x\n", atomic_compare)};
        end
        if (has_atomic_ack_eth()) begin
            s = {s, "  --- AtomicAckETH ---\n"};
            s = {s, $sformatf("  orig_data: 0x%016x\n", atomic_orig_data)};
        end
        if (has_deth()) begin
            s = {s, "  --- DETH ---\n"};
            s = {s, $sformatf("  q_key    : 0x%08x\n", deth_q_key)};
            s = {s, $sformatf("  src_qp   : 0x%06x\n", deth_src_qp)};
        end
        if (has_immdt())
            s = {s, $sformatf("  --- ImmDt: 0x%08x ---\n", imm_data)};
        if (has_ieth())
            s = {s, $sformatf("  --- IETH r_key: 0x%08x ---\n", ieth_r_key)};
        if (icrc_enable)
            s = {s, $sformatf("  icrc     : 0x%08x\n", icrc)};
        return s;
    endfunction

    virtual function string to_brief();
        string s = $sformatf("RoCEv2 %s qp:0x%06x psn:0x%06x", opcode.name(), dest_qp, psn);
        if (has_reth()) s = {s, $sformatf(" rkey:0x%08x", reth_r_key)};
        if (has_aeth()) s = {s, $sformatf(" syn:0x%02x", aeth_syndrome)};
        if (has_atomic_eth()) s = {s, $sformatf(" atomicRkey:0x%08x", atomic_r_key)};
        if (has_atomic_ack_eth()) s = {s, $sformatf(" origData:0x%016x", atomic_orig_data)};
        if (has_deth()) s = {s, $sformatf(" qkey:0x%08x srcQP:0x%06x", deth_q_key, deth_src_qp)};
        if (has_immdt()) s = {s, $sformatf(" imm:0x%08x", imm_data)};
        if (has_ieth()) s = {s, $sformatf(" invRkey:0x%08x", ieth_r_key)};
        return s;
    endfunction

    // =========================================================================
    // help — print opcode mapping and usage examples
    // =========================================================================
    static function void help();
        $display("============================================================================");
        $display(" RoCEv2 (IB Spec Ch9) — Opcode to Extended Header Mapping");
        $display("============================================================================");
        $display(" Opcode                        | RETH | AETH | Atomic | AtoAck | DETH | Imm | IETH");
        $display(" -------------------------------|------|------|--------|--------|------|-----|-----");
        $display(" RC_SEND_ONLY           (0x04) |      |      |        |        |      |     |     ");
        $display(" RC_SEND_ONLY_IMM       (0x05) |      |      |        |        |      |  v  |     ");
        $display(" RC_SEND_ONLY_INV       (0x17) |      |      |        |        |      |     |  v  ");
        $display(" RC_RDMA_WRITE_ONLY     (0x0A) |  v   |      |        |        |      |     |     ");
        $display(" RC_RDMA_WRITE_ONLY_IMM (0x0B) |  v   |      |        |        |      |  v  |     ");
        $display(" RC_RDMA_WRITE_FIRST    (0x06) |  v   |      |        |        |      |     |     ");
        $display(" RC_RDMA_WRITE_MIDDLE   (0x07) |      |      |        |        |      |     |     ");
        $display(" RC_RDMA_WRITE_LAST     (0x08) |      |      |        |        |      |     |     ");
        $display(" RC_RDMA_WRITE_LAST_IMM (0x09) |      |      |        |        |      |  v  |     ");
        $display(" RC_RDMA_READ_REQ       (0x0C) |  v   |      |        |        |      |     |     ");
        $display(" RC_RDMA_READ_RESP_ONLY (0x10) |      |  v   |        |        |      |     |     ");
        $display(" RC_ACK                 (0x11) |      |  v   |        |        |      |     |     ");
        $display(" RC_CMP_SWAP            (0x13) |      |      |   v    |        |      |     |     ");
        $display(" RC_FETCH_ADD           (0x14) |      |      |   v    |        |      |     |     ");
        $display(" RC_ATOMIC_ACK          (0x12) |      |  v   |        |   v    |      |     |     ");
        $display(" UD_SEND_ONLY           (0x64) |      |      |        |        |  v   |     |     ");
        $display(" UD_SEND_ONLY_IMM       (0x65) |      |      |        |        |  v   |  v  |     ");
        $display(" RC_CNP                 (0x81) |      |      |        |        |      |     |     ");
        $display("----------------------------------------------------------------------------");
        $display("");
        $display(" Usage Examples:");
        $display("   // RDMA Write");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_ROCEV2;");
        $display("       rocev2.opcode       == RC_RDMA_WRITE_ONLY;");
        $display("       rocev2.dest_qp      == 24'h000100;");
        $display("       rocev2.reth_va      == 64'hDEAD_BEEF_0000_0000;");
        $display("       rocev2.reth_r_key   == 32'h0000_1234;");
        $display("       rocev2.reth_dma_len == 32'd4096;");
        $display("   };");
        $display("");
        $display("   // RDMA Read Request");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_ROCEV2;");
        $display("       rocev2.opcode       == RC_RDMA_READ_REQ;");
        $display("       rocev2.reth_va      == 64'h0000_0000_1000_0000;");
        $display("       rocev2.reth_r_key   == 32'h0000_5678;");
        $display("       rocev2.reth_dma_len == 32'd2048;");
        $display("   };");
        $display("");
        $display("   // Atomic Compare & Swap");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_ROCEV2;");
        $display("       rocev2.opcode          == RC_CMP_SWAP;");
        $display("       rocev2.atomic_va       == 64'h0000_0000_4000_0000;");
        $display("       rocev2.atomic_r_key    == 32'h0000_AAAA;");
        $display("       rocev2.atomic_swap_add == 64'h2;  // new value");
        $display("       rocev2.atomic_compare  == 64'h1;  // expected old value");
        $display("   };");
        $display("");
        $display("   // UD Send");
        $display("   pkt.randomize() with {");
        $display("       pkt_kind == ETH_IPV4_UDP_ROCEV2;");
        $display("       rocev2.opcode      == UD_SEND_ONLY;");
        $display("       rocev2.deth_q_key  == 32'h0000_1111;");
        $display("       rocev2.deth_src_qp == 24'h000600;");
        $display("   };");
        $display("============================================================================");
    endfunction

    virtual function void verify(ref string errors[$], ref string warnings[$]);
        // Pad count should be 0-3
        if (pad_count > 3)
            errors.push_back($sformatf("RoCEv2 BTH: pad_count=%0d > 3", pad_count));
        // Destination QP
        if (dest_qp == 0)
            warnings.push_back("RoCEv2 BTH: dest_qp=0");
    endfunction

    virtual function void load_params(string path);
`ifdef AIP_CMDLINE_SV
        int __w;
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("opcode", path);
            if (__v != "") begin
                bit [7:0] __t = 8'(aip_str::str_to_num(__v, __w));
                opcode = rocev2_opcode_e'(__t);
            end
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("se", path);
            if (__v != "") se = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("mig_req", path);
            if (__v != "") mig_req = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pad_count", path);
            if (__v != "") pad_count = 2'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("tver", path);
            if (__v != "") tver = 4'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("pkey", path);
            if (__v != "") pkey = 16'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("dest_qp", path);
            if (__v != "") dest_qp = 24'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ack_req", path);
            if (__v != "") ack_req = 1'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("psn", path);
            if (__v != "") psn = 24'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("reth_va", path);
            if (__v != "") reth_va = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("reth_r_key", path);
            if (__v != "") reth_r_key = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("reth_dma_len", path);
            if (__v != "") reth_dma_len = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("aeth_syndrome", path);
            if (__v != "") aeth_syndrome = 8'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("aeth_msn", path);
            if (__v != "") aeth_msn = 24'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("imm_data", path);
            if (__v != "") imm_data = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("atomic_va", path);
            if (__v != "") atomic_va = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("atomic_r_key", path);
            if (__v != "") atomic_r_key = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("atomic_swap_add", path);
            if (__v != "") atomic_swap_add = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("atomic_compare", path);
            if (__v != "") atomic_compare = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("atomic_orig_data", path);
            if (__v != "") atomic_orig_data = 64'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("ieth_r_key", path);
            if (__v != "") ieth_r_key = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("deth_q_key", path);
            if (__v != "") deth_q_key = 32'(aip_str::str_to_num(__v, __w));
        end
        begin
            string __v = aip_cmdline#(int)::get_cmdline_string("deth_src_qp", path);
            if (__v != "") deth_src_qp = 24'(aip_str::str_to_num(__v, __w));
        end
`endif
    endfunction

endclass

`endif // ROCEV2_HEADER_SV
