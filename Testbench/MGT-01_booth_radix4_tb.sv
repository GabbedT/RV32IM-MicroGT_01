`timescale 1ns/1ps

module MGT_01_booth_radix4_tb ();
  
  localparam T = 10;

  //Inputs
  logic signed [XLEN - 1:0]        multiplier_i, multiplicand_i; 

  logic                            clk_i, clk_en_i;               //Clock signals
  logic                            rst_n_i;                       //Reset active low
  
  //Outputs
  logic signed [(XLEN * 2) - 1:0]  result_o;                      
  fu_state_e                       fu_state_o;                    //Functional unit state
  logic [4:0]                      counter_o;
  logic [XLEN:0]                   P_o;

  MGT_01_booth_radix4 uut (.*);

  //Test

    //Clock 
    always 
      begin
        clk_i = 1'b1;
        #(T / 2);
        clk_i = 1'b0;
        #(T / 2);
      end

    always @(posedge clk_i) 
      begin
        rst_n_i = 1'b0;
        clk_en_i = 1'b1;
        multiplier_i = 32'd0;
        multiplicand_i = 32'd0;
        
        #(2 * T);
        
        rst_n_i = 1'b1;
        clk_en_i = 1'b1;
        multiplier_i = 32'd10;
        multiplicand_i = 32'd20;        //RESULT:   0x0000000800000320
                                        //EXPECTED: 0x00000000000000C8
                                        //NOTE:     In the cycle before the end I got 0x0000002000000c80

        #(17 * T);
        
        multiplier_i = 32'd100;
        multiplicand_i = -32'd200;      //RESULT:   0x00000007ffffb1e0
                                        //EXPECTED: 0xFFFFFFFFFFFFB1E0
        
        #(17 * T);
        
        multiplier_i = 32'd150;
        multiplicand_i = 32'd1000;      //RESULT:   0x00000008000927c0
                                        //EXPECTED: 0x00000000000249F0
                                        //NOTE:     In the cycle before the end I got 0x0000002000249f00
        
        #(17 * T);
        
        multiplier_i = -32'd10;
        multiplicand_i = -32'd20;       //RESULT:   0x0000002000000323
                                        //EXPECTED: 0x00000000000000C8
                                        //NOTE:     In the cycle before the end I got 0x0000008000000c8f
        
        #(17 * T);
        
        multiplier_i = 32'hFFFFFFFF;
        multiplicand_i = 32'h80000000;  //RESULT:   0x0000000020000003
                                        //EXPECTED: 0x0000000080000000
                                        //NOTE:     In the cycle before the end I got 0x000000080000000f
        #(17 * T);

        $stop;
      end

endmodule