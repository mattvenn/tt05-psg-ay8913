// FROM General Instruments AY-3-8910 / 8912 Programmable Sound Generator (PSG) data Manual.
// Section 3.2 Noise Generator Control
// ...
// Note that the 6-bit value in R11 is a period value-the higher the value in the register,
// the lower the resultant noise frequency. Note also that, as with the Tone Period,
// the lowest period value is 00001 (divide by 1); the highest period value is 11111 (divide by 3110).

// LFSR in hardware implementation uses 2 taps and adds extra 1 when LFSR is equal to 0.

// MAME does not check for LFSR==0 and uses single XOR with 2 taps.
// Instead MAME initialises LFSR with 1 upon reset. This is not a bug!
// The following Python code validates that if LFSR is initialised with 1
//  - LFSR will never reach 0 and
//  - the cycle is 131070 iterations before LFSR reaches 1 again
//
//  lfsr = 1
//  for x in range(65535*16): lfsr = lfsr >> 1 | (((lfsr&1) ^ ((lfsr>>3)&1))<<16); print (lfsr,x) if lfsr <= 1 else None 

module noise #( parameter LFSR_BITS = 17, LFSR_TAP0 = 0, LFSR_TAP1 = 3, parameter PERIOD_BITS = 5 ) (
    input  wire clk,
    input  wire reset,
    input  wire [PERIOD_BITS-1:0] period,

    output wire  out
);
    wire lfsr_shift_trigger;
    tone #(.PERIOD_BITS(PERIOD_BITS)) tone (
        .clk(clk),
        .reset(reset),
        .period(period),
        .out(lfsr_shift_trigger));

    reg [LFSR_BITS-1:0] lfsr;
    wire is_lfsr_zero = (lfsr == 0); // more readable, but equivalent to the hardware implementation ~(|lfsr)
    wire lfsr_shift_in = (lfsr[LFSR_TAP0] ^ lfsr[LFSR_TAP1]) | is_lfsr_zero;
    
    always @(posedge lfsr_shift_trigger) begin
        if (reset)      // @TODO: reset should happen on the master clock
            lfsr <= 0;
        else
            lfsr <= {lfsr_shift_in, lfsr[LFSR_BITS-1:1]};
    end

    assign out = ~lfsr[0];
endmodule
