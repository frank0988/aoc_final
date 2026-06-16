`timescale 1ns/1ps

package weight_tb_pkg;
    import rlc_encode_pkg::*;

    function automatic rlc_vec_t weight_zero_vec();
        return rlc_zero_vec(8'd0);
    endfunction
endpackage
