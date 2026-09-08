// src/parser/packet_comparator.sv
`ifndef PACKET_COMPARATOR_SV
`define PACKET_COMPARATOR_SV

`include "core/packet.sv"

class packet_comparator;

    // Control: whether to print PASS results (errors always print)
    bit print_pass = 0;

    // Compare two packets, return list of field-level differences
    function void compare(packet a, packet b, ref diff_entry_t diffs[$]);
        diffs.delete();

        // Check layer count
        if (a.layer_stack.size() != b.layer_stack.size()) begin
            diff_entry_t d;
            d.layer = PROTO_RAW_PAYLOAD;
            d.field_name = "layer_count";
            d.val_a = $sformatf("%0d", a.layer_stack.size());
            d.val_b = $sformatf("%0d", b.layer_stack.size());
            diffs.push_back(d);
        end

        // Compare each layer field-by-field
        begin
            int min_layers = (a.layer_stack.size() < b.layer_stack.size()) ?
                              a.layer_stack.size() : b.layer_stack.size();

            for (int i = 0; i < min_layers; i++) begin
                // Check proto_type mismatch
                if (a.layer_stack[i].proto_type != b.layer_stack[i].proto_type) begin
                    diff_entry_t d;
                    d.layer = a.layer_stack[i].proto_type;
                    d.field_name = $sformatf("layer[%0d].proto_type", i);
                    d.val_a = a.layer_stack[i].proto_type.name();
                    d.val_b = b.layer_stack[i].proto_type.name();
                    diffs.push_back(d);
                    continue;
                end

                // Quick check: if layers are identical, skip
                if (a.layer_stack[i].compare(b.layer_stack[i])) continue;

                // Field-level diff: parse to_string() output line by line
                diff_fields_by_string(a.layer_stack[i], b.layer_stack[i], i, diffs);
            end
        end

        // Compare raw_data (payload) byte-by-byte
        if (a.raw_data.size() != b.raw_data.size()) begin
            diff_entry_t d;
            d.layer = PROTO_RAW_PAYLOAD;
            d.field_name = "raw_data_size";
            d.val_a = $sformatf("%0d bytes", a.raw_data.size());
            d.val_b = $sformatf("%0d bytes", b.raw_data.size());
            diffs.push_back(d);
        end else begin
            // Same size — check payload content after headers
            int hdr_len_a = 0, hdr_len_b = 0;
            int first_diff = -1;
            int diff_count = 0;
            foreach (a.layer_stack[i]) hdr_len_a += a.layer_stack[i].get_header_length();
            foreach (b.layer_stack[i]) hdr_len_b += b.layer_stack[i].get_header_length();
            // Compare bytes after headers (payload region)
            if (hdr_len_a == hdr_len_b) begin
                for (int i = hdr_len_a; i < a.raw_data.size(); i++) begin
                    if (a.raw_data[i] != b.raw_data[i]) begin
                        if (first_diff < 0) first_diff = i - hdr_len_a;
                        diff_count++;
                    end
                end
                if (diff_count > 0) begin
                    diff_entry_t d;
                    d.layer = PROTO_RAW_PAYLOAD;
                    d.field_name = "payload";
                    d.val_a = $sformatf("%0d bytes differ (first at offset %0d)", diff_count, first_diff);
                    d.val_b = $sformatf("payload_size=%0d", a.raw_data.size() - hdr_len_a);
                    diffs.push_back(d);
                end
            end
        end
    endfunction

    // Field-level diff using to_string() parsing
    // Each header's to_string() outputs lines like: "  field_name : value\n"
    // We compare line-by-line to find specific field differences.
    protected function void diff_fields_by_string(
        protocol_base ha, protocol_base hb,
        int layer_idx, ref diff_entry_t diffs[$]
    );
        string str_a, str_b;
        string lines_a[$], lines_b[$];

        str_a = ha.to_string();
        str_b = hb.to_string();

        split_lines(str_a, lines_a);
        split_lines(str_b, lines_b);

        // Compare matching lines
        begin
            int max_lines = (lines_a.size() > lines_b.size()) ? lines_a.size() : lines_b.size();
            int min_lines = (lines_a.size() < lines_b.size()) ? lines_a.size() : lines_b.size();

            for (int i = 0; i < min_lines; i++) begin
                if (lines_a[i] != lines_b[i]) begin
                    string fname_a, fval_a, fname_b, fval_b;
                    parse_field_line(lines_a[i], fname_a, fval_a);
                    parse_field_line(lines_b[i], fname_b, fval_b);

                    if (fname_a.len() > 0) begin
                        diff_entry_t d;
                        d.layer = ha.proto_type;
                        d.field_name = $sformatf("layer[%0d].%s", layer_idx, fname_a);
                        d.val_a = fval_a;
                        d.val_b = fval_b;
                        diffs.push_back(d);
                    end
                end
            end

            // Extra lines in one side (different header lengths)
            for (int i = min_lines; i < max_lines; i++) begin
                diff_entry_t d;
                d.layer = ha.proto_type;
                d.field_name = $sformatf("layer[%0d].extra_field", layer_idx);
                d.val_a = (i < lines_a.size()) ? lines_a[i] : "(absent)";
                d.val_b = (i < lines_b.size()) ? lines_b[i] : "(absent)";
                diffs.push_back(d);
            end
        end
    endfunction

    // Split string by newline
    protected function void split_lines(string s, ref string lines[$]);
        string line = "";
        lines.delete();
        for (int i = 0; i < s.len(); i++) begin
            if (s[i] == "\n") begin
                // Skip header line (=== PROTO_XXX ===) and empty lines
                if (line.len() > 0 && line[0] != "=" && line[0] != "-")
                    lines.push_back(line);
                line = "";
            end else begin
                line = {line, string'(s[i])};
            end
        end
        if (line.len() > 0 && line[0] != "=" && line[0] != "-")
            lines.push_back(line);
    endfunction

    // Parse "  field_name : value" into name and value
    protected function void parse_field_line(string line, ref string fname, ref string fval);
        int colon_pos = -1;
        fname = "";
        fval = "";

        // Find first ":"
        for (int i = 0; i < line.len(); i++) begin
            if (line[i] == ":") begin
                colon_pos = i;
                break;
            end
        end

        if (colon_pos < 0) begin
            fname = line;  // No colon — use whole line
            return;
        end

        // Extract name (trim leading spaces)
        begin
            string raw_name = line.substr(0, colon_pos - 1);
            int start = 0;
            // Trim leading spaces
            for (int i = 0; i < raw_name.len(); i++) begin
                if (raw_name[i] != " ") begin start = i; break; end
            end
            // Trim trailing spaces
            begin
                int end_pos = raw_name.len() - 1;
                for (int i = raw_name.len() - 1; i >= start; i--) begin
                    if (raw_name[i] != " ") begin end_pos = i; break; end
                end
                if (end_pos >= start)
                    fname = raw_name.substr(start, end_pos);
            end
        end

        // Extract value (trim leading space after colon)
        if (colon_pos + 1 < line.len()) begin
            int start = colon_pos + 1;
            // Skip leading spaces
            for (int i = start; i < line.len(); i++) begin
                if (line[i] != " ") begin start = i; break; end
            end
            fval = line.substr(start, line.len() - 1);
        end
    endfunction

    // Print diffs in human-readable format
    function string diff_to_string(diff_entry_t diffs[$]);
        string s = "";
        if (diffs.size() == 0) begin
            s = "COMPARE RESULT: PASS — packets are identical\n";
        end else begin
            s = $sformatf("COMPARE RESULT: FAIL — %0d difference(s) found\n", diffs.size());
            s = {s, "---------------------------------------------------------------\n"};
            foreach (diffs[i]) begin
                s = {s, $sformatf("  ERROR [%s] %s\n", diffs[i].layer.name(), diffs[i].field_name)};
                s = {s, $sformatf("      expect: %s\n", diffs[i].val_a)};
                s = {s, $sformatf("      actual: %s\n", diffs[i].val_b)};
            end
            s = {s, "---------------------------------------------------------------\n"};
        end
        return s;
    endfunction

    // Convenience: compare and print in one call
    // Returns 1 if identical, 0 if different
    // Errors always print. Pass results only print when print_pass=1.
    function bit compare_and_print(packet a, packet b);
        diff_entry_t diffs[$];
        bit pass;
        compare(a, b, diffs);
        pass = (diffs.size() == 0);

        if (!pass) begin
            // FAIL: always print
            string s = "";
            s = {s, $sformatf("PKT_A (expect): %s\n", a.to_brief())};
            s = {s, $sformatf("PKT_B (actual): %s\n", b.to_brief())};
            s = {s, "\n"};
            s = {s, diff_to_string(diffs)};
            $display("%s", s);
        end else if (print_pass) begin
            // PASS: only print when enabled
            $display("COMPARE RESULT: PASS — %s", a.to_brief());
        end

        return pass;
    endfunction

endclass

`endif // PACKET_COMPARATOR_SV
