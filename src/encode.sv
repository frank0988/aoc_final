`timescale 1ns/1ps

package rlc_encode_pkg;
    localparam int RLC_LANES      = 7;
    localparam int RLC_LANE_BITS  = 8;
    localparam int RLC_VEC_BITS   = RLC_LANES * RLC_LANE_BITS;
    localparam int RLC_RUN_BITS   = 7;
    localparam int RLC_TOKEN_BITS = 64;
    localparam int RLC_MAX_RUN    = (1 << RLC_RUN_BITS) - 1;

    typedef logic [RLC_VEC_BITS-1:0]   rlc_vec_t;
    typedef logic [RLC_TOKEN_BITS-1:0] rlc_token_t;

    function automatic rlc_vec_t rlc_zero_vec(input logic [RLC_LANE_BITS-1:0] zero_lane);
        rlc_vec_t vec;
        for (int lane = 0; lane < RLC_LANES; lane++) begin
            vec[lane * RLC_LANE_BITS +: RLC_LANE_BITS] = zero_lane;
        end
        return vec;
    endfunction

    function automatic bit rlc_vec_is_zero(
        input rlc_vec_t vec,
        input rlc_vec_t zero_vec
    );
        return vec == zero_vec;
    endfunction

    function automatic rlc_token_t rlc_make_token(
        input bit last,
        input int unsigned zero_run,
        input rlc_vec_t payload
    );
        rlc_token_t token;
        token = '0;
        token[0]     = last;
        token[56:1]  = payload;
        token[63:57] = zero_run[RLC_RUN_BITS-1:0];
        return token;
    endfunction
endpackage
