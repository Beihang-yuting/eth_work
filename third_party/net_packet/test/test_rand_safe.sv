// test_rand_safe.sv — 验证默认 randomize (PKT_CAT_ALL) 不再撞未实现协议
//   通过判据: 500 次 randomize 全成功 且 run log 无 "unsupported protocol"
`include "packet.sv"

module test_rand_safe;
    initial begin
        packet pkt;
        int n_ok = 0;
        for (int i = 0; i < 500; i++) begin
            pkt = new();
            if (!pkt.randomize()) $display("[FAIL] randomize iter %0d failed", i);
            else n_ok++;
        end
        $display("RAND_OK %0d/500", n_ok);
        $display("DONE — 若上方无 'unsupported protocol' warning 则修复生效");
        $finish;
    end
endmodule
