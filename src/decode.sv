`timescale 1ns/1ps

package rlc_decode_pkg;
    import rlc_encode_pkg::*;

    function automatic bit rlc_token_term(input rlc_token_t token);
        return token[0];
    endfunction

    function automatic bit rlc_token_last(input rlc_token_t token);
        return !rlc_token_term(token);
    endfunction

    function automatic int unsigned rlc_token_run(input rlc_token_t token);
        return int'(token[63:57]);
    endfunction

    function automatic rlc_vec_t rlc_token_payload(input rlc_token_t token);
        return token[56:1];
    endfunction

    function automatic logic [RLC_LANE_BITS-1:0] rlc_vec_lane(
        input rlc_vec_t vec,
        input int unsigned lane
    );
        return vec[(RLC_LANES - 1 - lane) * RLC_LANE_BITS +: RLC_LANE_BITS];
    endfunction
endpackage
