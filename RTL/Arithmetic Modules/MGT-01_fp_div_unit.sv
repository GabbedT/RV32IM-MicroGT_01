////////////////////////////////////////////////////////////////////////////////
// Creator:        Gabriele Tripi - gabrieletripi02@gmail.com                 //
//                                                                            //
// Design Name:    Floating point division unit                               //
// Project Name:   MicroGT-01                                                 //
// Language:       SystemVerilog                                              //
//                                                                            //
// Description:    This unit perform a simple floating point division.        //
//                                                                            //
// Dependencies:   MGT-01_nr_divider.sv                                       //
////////////////////////////////////////////////////////////////////////////////

`include "Primitives/Modules_pkg.svh"
`include "Primitives/Instruction_pkg.svh"

module MGT_01_fp_div_unit
( //Inputs
  input  float_t    dividend_i, divisor_i, 

  input  logic      clk_i, clk_en_i,               //Clock signals
  input  logic      rst_n_i,                       //Reset active low

  //Outputs
  output float_t    to_round_unit_o,   //Result 
  output logic      valid_o,
  output fu_state_e fu_state_o,
  output logic      overflow_o, 
  output logic      underflow_o, 
  output logic      invalid_op_o,
  output logic      zero_divide_o 
);

  typedef enum logic [2:0] {IDLE, PREPARE, DIVIDE, NORMALIZE, VALID} fsm_state_e;

  fsm_state_e crt_state, nxt_state;

  // IDLE: The unit is waiting for data
  // PREPARE: Preparing the data to be computed (sign extraction, add exponent)
  // DIVIDE: Divide the mantissas
  // NORMALIZE: Normalize the result

  ///////////////
  // FSM LOGIC //
  ///////////////

  logic valid_mantissa;         //Divided mantissa is valid
  logic zero_divide_mantissa;   //Divide a non zero mantissa by zero (when the divisor is 0)

  logic rst_n_dly;      //Reset delayed

      // We delay the reset signals by 1 cycle because the FSM should
      // stay 2 cycles in the IDLE stage when resetted

      always_ff @(posedge clk_i)
        begin
          rst_n_dly <= rst_n_i;
        end

      //State register
      always_ff @(posedge clk_i)
        begin : STATE_REG
          if (!rst_n_i)
            crt_state <= IDLE;
          else if (clk_en_i)   
            crt_state <= nxt_state;
        end : STATE_REG

      //Next state logic
      always_comb 
        begin
          unique case (crt_state)

            IDLE:       nxt_state = (~rst_n_dly) ? IDLE : PREPARE;

            PREPARE:    nxt_state = DIVIDE; 

            //If the result of the divider is valid, go to next state
            DIVIDE:     nxt_state = valid_mantissa ? NORMALIZE : DIVIDE; 

            NORMALIZE:  nxt_state = VALID;

            VALID:      nxt_state = IDLE;

          endcase
        end


  effective_float_t dividend_in, divisor_in;
  effective_float_t dividend_out, divisor_out;

  float_t result, op_A_out, op_B_out;

      always_ff @(posedge clk_i)
        begin 
          if ((crt_state == PREPARE) & clk_en_i)
            begin 
              op_A_out <= dividend_i;
              op_B_out <= divisor_i;
            end
        end

  //OR the exponent to detect if the number is a 0 (hidden bit is 0 too)
  assign dividend_in = {dividend_i.sign, dividend_i.exponent, |dividend_i.exponent, dividend_i.mantissa};
  
  assign divisor_in = {divisor_i.sign, divisor_i.exponent, |divisor_i.exponent, divisor_i.mantissa};
  
      always_ff @(posedge clk_i) 
        begin : DATA_REGISTER
          if (!rst_n_i)
            begin 
              dividend_out <= 33'b0;
              divisor_out <= 33'b0;
            end
          if (clk_en_i & (crt_state == IDLE))
            begin 
              dividend_out <= dividend_in;
              divisor_out <= divisor_in;
            end
        end : DATA_REGISTER

  //Result of the 32x32 divider
  logic [XLEN - 1:0] result_mantissa_full;

  logic [23:0] result_mantissa, norm_mantissa;

  //Enable the division
  logic div_en;

  assign div_en = (crt_state == DIVIDE);

  MGT_01_nr_divider mantissa_divider (
    .dividend_i    ( {8'b0, dividend_out.hidden_bit, dividend_out.mantissa} ),
    .divisor_i     ( {8'b0, divisor_out.hidden_bit, divisor_out.mantissa}   ),
    .clk_i         ( clk_i                                                  ),
    .clk_en_i      ( div_en                                                 ),
    .rst_n_i       ( rst_n_i                                                ),
    .quotient_o    ( result_mantissa_full                                   ),
    .valid_o       ( valid_mantissa                                         ),
    .zero_divide_o ( zero_divide_mantissa                                   )
  );
  
  assign valid_o = (crt_state == VALID);
  
  assign fu_state = (crt_state == IDLE) ? FREE : BUSY;

  logic [7:0] result_exponent, result_exponent_bias, norm_exponent;
  logic       result_sign;
  logic [4:0] leading_zero;

  //XOR the sign bits: if different the sign bit is 1 (-) else the sign bit is (+)
  assign result_sign = dividend_out.sign ^ divisor_out.sign;

  //Valid bits are [23:0] (comprehend the hidden bit)
  assign result_mantissa = result_mantissa_full[23:0];

  //Subtract the exponents since it is a division
  assign result_exponent = dividend_out.exponent - divisor_out.exponent;

      always_comb
        begin : BIAS_LOGIC
          case ({dividend_out.exponent[7], divisor_out.exponent[7]})

            // Because the sign are the same and we are performing a division we are doing (EXa + BIAS) - (EXb + BIAS) = EXa - EXb
            // Thus we need to add the bias to obtain the biased exponent
            2'b00, 2'b11: result_exponent_bias = result_exponent + BIAS;

            // Because the sign are different and we are performing a division we are doing (EXa + BIAS) + (EXb + BIAS) = EXa + EXb + 2*BIAS
            // Thus we need to subtract the bias to obtain the biased exponent
            2'b10, 2'b01: result_exponent_bias = result_exponent - BIAS;

          endcase
        end : BIAS_LOGIC

      always_comb
        begin : NORMALIZE_LOGIC
          unique casez (result_mantissa)    //Leading zero encoder

            24'b1???????????????????????:  leading_zero = 5'd0;
            24'b01??????????????????????:  leading_zero = 5'd1;
            24'b001?????????????????????:  leading_zero = 5'd2;
            24'b0001????????????????????:  leading_zero = 5'd3;
            24'b00001???????????????????:  leading_zero = 5'd4;
            24'b000001??????????????????:  leading_zero = 5'd5;
            24'b0000001?????????????????:  leading_zero = 5'd6;
            24'b00000001????????????????:  leading_zero = 5'd7;
            24'b000000001???????????????:  leading_zero = 5'd8;
            24'b0000000001??????????????:  leading_zero = 5'd9;
            24'b00000000001?????????????:  leading_zero = 5'd10;
            24'b000000000001????????????:  leading_zero = 5'd11;
            24'b0000000000001???????????:  leading_zero = 5'd12;
            24'b00000000000001??????????:  leading_zero = 5'd13;
            24'b000000000000001?????????:  leading_zero = 5'd14;
            24'b0000000000000001????????:  leading_zero = 5'd15;
            24'b00000000000000001???????:  leading_zero = 5'd16;
            24'b000000000000000001??????:  leading_zero = 5'd17;
            24'b0000000000000000001?????:  leading_zero = 5'd18;
            24'b00000000000000000001????:  leading_zero = 5'd19;
            24'b000000000000000000001???:  leading_zero = 5'd20;
            24'b0000000000000000000001??:  leading_zero = 5'd21;
            24'b00000000000000000000001?:  leading_zero = 5'd22;
            24'b000000000000000000000001:  leading_zero = 5'd23;
            24'b000000000000000000000000:  leading_zero = 5'd24;

          endcase
                  
          norm_mantissa = result_mantissa << leading_zero;
          norm_exponent = result.exponent - leading_zero; 

        end : NORMALIZE_LOGIC


      always_ff @(posedge clk_i)
        begin 
          if (!rst_n_i)
            result <= 32'b0;
          if (clk_en_i)
            begin 
              if (crt_state == PREPARE)
                begin 
                  result.sign <= result_sign;
                  result.exponent <= result_exponent_bias;
                end
              else if (crt_state == NORMALIZE)
                begin 
                  result.exponent <= norm_exponent;
                  result.mantissa <= norm_mantissa[22:0];
                end
            end
        end

  assign zero_divide_o = zero_divide_mantissa & (~|divisor_out.exponent);

      always_comb
        begin 
          casez ({dividend_out, divisor_out})

            {ZERO, ZERO},
            {INFINITY, INFINITY}:   begin 
                                      to_round_unit_o = Q_NAN;
                                      overflow_o = 1'b0;
                                      underflow_o = 1'b0;
                                      invalid_op_o = 1'b1;
                                    end

            {32'b?, P_INFTY}:       begin 
                                      to_round_unit_o = P_ZERO;
                                      overflow_o = 1'b0;
                                      underflow_o = 1'b0;
                                      invalid_op_o = 1'b0;
                                    end

            {32'b?, N_INFTY}:       begin 
                                      to_round_unit_o = N_ZERO;
                                      overflow_o = 1'b0;
                                      underflow_o = 1'b0;
                                      invalid_op_o = 1'b0;
                                    end

            {SIGN_NAN, 32'b?},
            {32'b?, SIGN_NAN}:    begin 
                                      to_round_unit_o = Q_NAN;
                                      overflow_o = 1'b0;
                                      underflow_o = 1'b0;
                                      invalid_op_o = 1'b1;
                                    end

            default:                begin 
                                      //Exclude the sign bit
                                      to_round_unit_o = (~|dividend_out[30:0]) ? 32'b0 : result;
  
                                      //If the exponent of the dividend is positive and the divisor one's is negative (Ex: +2*10^9 / 2*10^-5 = 2*10^14)
                                      //If the result exponent is negative that means we have an overflow
                                      overflow_o = (dividend_out.exponent[7] & (~divisor_out.exponent[7])) & (~result.exponent[7]);

                                      //If the exponent of the result has all bits cleared and the mantissa's bits are not we have an underflow
                                      underflow_o = (~|result.exponent) & (|result.mantissa);              
                                      invalid_op_o = 1'b0;
                                    end
          endcase
        end

endmodule