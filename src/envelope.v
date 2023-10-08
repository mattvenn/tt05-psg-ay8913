// Envelope shapes:
//     Continue
//     | Attack
//     | | Alternate
//     | | | Hold
//     0 0 x x  \___
//     0 1 x x  /___
//     1 0 0 0  \\\\
//     1 0 0 1  \___
//     1 0 1 0  \/\/
//     1 0 1 1  \```
//     1 1 0 0  ////
//     1 1 0 1  /```
//     1 1 1 0  /\/\
//     1 1 1 1  /___

// Continue == 0
//     0 0 x x  \___ -> 1 0 0 1
//     0 1 x x  /___ -> 1 1 1 1
// Hold' = !Continue, Alternate' = Attack

// Hold == 1
//       Attack'
//       | Alternate'
//       0 0 1  \___
//       0 1 1  \```
//       1 0 1  /```
//       1 1 1  /___

module envelope #( parameter PERIOD_BITS = 16, parameter ENVELOPE_BITS = 4 ) (
    input  wire clk,
    input  wire reset,

    input  wire hold,
    input  wire alternate,
    input  wire attack,
    input  wire continue_,

    input  wire [PERIOD_BITS-1:0] period,

    output wire [ENVELOPE_BITS-1:0] out
);
    // handle 'Continue == 0' by mapping to counterpart 'Continue == 1' signals
    // that produce the same envelopes
    //     Continue
    //     | Attack
    //     | | Alternate
    //     | | | Hold
    //     0 0 x x  \___ -> 1 0 0 1
    //     0 1 x x  /___ -> 1 1 1 1
    // if Continue == 0 then Hold' = !Continue, Alternate' = Attack
    wire hold_      =   hold || !continue_;
    wire alternate_ =   continue_ ? alternate : attack;
    wire attack_    =   attack;

    // handle 'Hold == 1'
    //       Attack'
    //       | Alternate'
    //       0 0 1  \___
    //       0 1 1  \```
    //       1 0 1  /```
    //       1 1 1  /___
    wire hold__     =   hold_;
    wire alternate__=   hold_ ? ~alternate_ : alternate_;
    wire attack__   =   attack_;

    wire advance_envelope;
    tone #(.COUNTER_BITS(PERIOD_BITS)) tone (
        .clk(clk),
        .reset(reset),
        .period(period),
        .out(advance_envelope));

    reg invert_output;
    reg stop;
    reg [ENVELOPE_BITS-1:0] envelope_counter;
    always @(posedge advance_envelope) begin
        if (reset) begin
            stop <= 0;
            envelope_counter <= 0;
            invert_output <= !attack__;
        end else begin
            if (envelope_counter == MAX_VALUE) begin
                // if (hold_)
                //     invert_output <= attack_ ^ alternate_;
                // else if (alternate_)
                if (alternate__)
                    invert_output <= ~invert_output;
            end

            if (!(hold__ && stop))
                {stop, envelope_counter} <= envelope_counter + 1'b1;
            // else
            //     envelope_counter <= 0;
        end
    end

    localparam MAX_VALUE = {ENVELOPE_BITS{1'b1}};
    assign out =
        invert_output ? MAX_VALUE - envelope_counter : envelope_counter;

endmodule