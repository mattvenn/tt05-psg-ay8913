/* verilator lint_off WIDTH */
`default_nettype none

module tt_um_rejunity_ay8913 #( parameter DA7_DA4_UPPER_ADDRESS_MASK = 4'b0000,
                                parameter NUM_TONES = 3, parameter NUM_NOISES = 1,
                                parameter ATTENUATION_CONTROL_BITS = 4,
                                parameter FREQUENCY_COUNTER_BITS = 10, 
                                parameter NOISE_CONTROL_BITS = 3,
                                parameter CHANNEL_OUTPUT_BITS = 8,
                                parameter MASTER_OUTPUT_BITS = 7
) (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    assign uio_oe[7:0] = 8'b1111_1100; // Bidirectional path set to output, except the first BDIR pin and second BC1 pin
    assign uio_out[7:0] = {8{1'b0}};
    wire reset = ! rst_n;

    wire [7:0] data = ui_in;

    // AY-3-819x Bus Control Decode
    // NOTE: AY-3-819x has BC2 line to match design of CP1610 CPU, but in AY-3-8193 BC2 is always pulled high
    // BDIR  BC1
    //   0    0    Inactive
    //   0    1    Read from Register Array  (NOT IMPLEMENTED!)
    //   1    0    Write to Register Array
    //   1    1    Latch Register Address
    wire bdir = uio_in[0];
    wire bc1 = uio_in[1];
    wire bus_inactive   = !bdir && !bc1;
    wire bus_read       = !bdir &&  bc1;
    wire bus_write      =  bdir && !bc1;
    wire bus_latch_reg  =  bdir &&  bc1;

    wire cs = (data[7:4] == DA7_DA4_UPPER_ADDRESS_MASK);// NOTE: A8 and A9 are NOT IMPLEMENTED!
    wire latch = bus_latch_reg && cs;
    wire write = bus_write && active;                   // NOTE: chip must be in active state
                                                        // in order to accept writes to the register file 

    reg [8:0] clk_counter;
    wire clk_16  = clk_counter[4];  // master clock divided by  16 for tunes and noise
    wire clk_256 = clk_counter[8];  // master clock divided by 256 for envelope

    reg [3:0] latched_register;
    reg [7:0] register[15:0];       // 82 bits are used out of 128
    reg active;                     // chip becomes active during the Latch Register Address phase
                                    // IFF cs==1 ({A9,A8,DA7..DA4} matches the chip mask)
    reg restart_envelope;

    always @(posedge clk) begin
        if (reset) begin
            clk_counter <= 0;
            latched_register <= 0;
            for (integer i = 0; i < 16; i = i + 1)
                register[i] <= 0;
            active <= 0;
            restart_envelope <= 0;
        end else begin
            clk_counter <= clk_counter + 1;                 // provides clk_16 and clk_256 dividers

            if (bus_latch_reg)                              // chip becomes active for subsequent reads/writes
                active <= cs;                               // IFF cs==1, during the Latch Register Address phase
                                                            // otherwise future data reads/writes will be ignored

            if (latch)
                latched_register <= data[3:0];
            else if (write)
                register[latched_register] <= data;

            restart_envelope <= write &&                    // restart envelope
                                latched_register == 4'd13;  // when data is written to R13 Envelope Shape register
        end
    end

    // AY-3-819x Register Array
    //     7 6 5 4 3 2 1 0
    // R0  x x x x x x x x Channel A Tone Period, Fine Tune
    // R1          x x x x                        Coarse Tune
    // R2  x x x x x x x x Channel B Tone Period, Fine Tune
    // R3          x x x x                        Coarse Tune
    // R4  x x x x x x x x Channel C Tone Period, Fine Tune
    // R5          x x x x                        Coarse Tune
    // R6        x x x x x Noise Period
    // R7      x x x x x x Mixer (signals inverted): Noise /C, /B, /A; Tone /C, /B, /A
    // R8        x x x x x Channel A Amplitude
    // R9        x x x x x Channel B Amplitude
    // R10       x x x x x Channel C Amplitude
    // R11 x x x x x x x x Envelop Period, Fine Tune
    // R12 x x x x x x x x                 Coarse Tune
    // R13         x x x x Envelope Shape / Cycle

    wire [11:0]  tone_period_A, tone_period_B, tone_period_C;
    wire [4:0]   noise_period;
    wire         tone_disable_A, tone_disable_B, tone_disable_C;
    wire         noise_disable_A, noise_disable_B, noise_disable_C;
    wire         envelope_A, envelope_B, envelope_C;
    wire [3:0]   amplitude_A, amplitude_B, amplitude_C;
    wire [15:0]  envelope_period;
    wire         envelope_continue, envelope_attack, envelope_alternate, envelope_hold;

    assign tone_period_A[11:0] = {register[1][3:0], register[0][7:0]};
    assign tone_period_B[11:0] = {register[3][3:0], register[2][7:0]};
    assign tone_period_C[11:0] = {register[5][3:0], register[4][7:0]};
    assign noise_period[4:0]   = register[6][4:0];
    assign {noise_disable_C,
            noise_disable_B,
            noise_disable_A,
            tone_disable_C,
            tone_disable_B,
            tone_disable_A} = ! register[7][5:0];
    assign {envelope_A, amplitude_A[3:0]} = register[ 8][4:0];
    assign {envelope_B, amplitude_B[3:0]} = register[ 9][4:0];
    assign {envelope_C, amplitude_C[3:0]} = register[10][4:0];
    assign envelope_period[15:0] = {register[12][7:0], register[11][7:0]};
    assign {envelope_continue,
            envelope_attack,
            envelope_alternate,
            envelope_hold} = register[13][3:0];


    // Tone, noise & envelope generators
    wire tone_A, tone_B, tone_C, noise;
    tone #(.COUNTER_BITS(12)) tone_A_generator (
        .clk(clk_16),
        .reset(reset),
        .period(tone_period_A),
        .out(tone_A)
        );
    tone #(.COUNTER_BITS(12)) tone_B_generator (
        .clk(clk_16),
        .reset(reset),
        .period(tone_period_B),
        .out(tone_B)
        );
    tone #(.COUNTER_BITS(12)) tone_C_generator (
        .clk(clk_16),
        .reset(reset),
        .period(tone_period_C),
        .out(tone_C)
        );

    noise #(.COUNTER_BITS(5)) noise_generator (
        .clk(clk_16),
        .reset(reset),
        .period(noise_period),
        .out(noise)
        );

    wire [3:0] envelope; // NOTE: Y2149 envelope outputs 5 bits, but programmable amplitude is only 4 bits!
    envelope #(.PERIOD_BITS(16), .ENVELOPE_BITS(4)) envelope_generator (
        .clk(clk_256),
        .reset(reset | restart_envelope),
        .continue_(envelope_continue),
        .attack(envelope_attack),
        .alternate(envelope_alternate),
        .hold(envelope_hold),
        .period(envelope_period),
        .out(envelope)
        );

    // FROM https://github.com/mamedev/mame/blob/master/src/devices/sound/ay8910.cpp ay8910_device::sound_stream_update
    // The 8910 has three outputs, each output is the mix of one of the three
    // tone generators and of the (single) noise generator. The two are mixed
    // BEFORE going into the DAC. The formula to mix each channel is:
    // (ToneOn | ToneDisable) & (NoiseOn | NoiseDisable).
    // Note that this means that if both tone and noise are disabled, the output
    // is 1, not 0, and can be modulated changing the volume.
    wire channel_A = (tone_disable_A | tone_A) & (noise_disable_A | noise);
    wire channel_B = (tone_disable_B | tone_B) & (noise_disable_B | noise);
    wire channel_C = (tone_disable_C | tone_C) & (noise_disable_C | noise);

    wire [CHANNEL_OUTPUT_BITS-1:0] volume_A, volume_B, volume_C;
    attenuation #(.VOLUME_BITS(CHANNEL_OUTPUT_BITS)) attenuation_A (
        .in(channel_A),
        .control(envelope_A ? envelope: amplitude_A),
        .out(volume_A)
        );
    attenuation #(.VOLUME_BITS(CHANNEL_OUTPUT_BITS)) attenuation_B (
        .in(channel_B),
        .control(envelope_B ? envelope: amplitude_B),
        .out(volume_B)
        );
    attenuation #(.VOLUME_BITS(CHANNEL_OUTPUT_BITS)) attenuation_C (
        .in(channel_C),
        .control(envelope_C ? envelope: amplitude_C),
        .out(volume_C)
        );

    wire [CHANNEL_OUTPUT_BITS-1:0] master = volume_A + volume_B + volume_C;

    
    assign uo_out[7:0] = master;

    // // sum up all the channels, clamp to the highest value when overflown
    // localparam OVERFLOW_BITS = $clog2(NUM_CHANNELS);
    // localparam ACCUMULATOR_BITS = CHANNEL_OUTPUT_BITS + OVERFLOW_BITS;
    // wire [ACCUMULATOR_BITS-1:0] master;
    // assign master = (volumes[0] + volumes[1] + volumes[2] + volumes[3]);
    // assign uo_out[7:1] = (master[ACCUMULATOR_BITS-1 -: OVERFLOW_BITS] == 0) ? master[CHANNEL_OUTPUT_BITS-1 -: MASTER_OUTPUT_BITS] : {MASTER_OUTPUT_BITS{1'b1}};

    // pwm #(.VALUE_BITS(MASTER_OUTPUT_BITS)) pwm (
    //     .clk(clk),
    //     .reset(reset),
    //     .value(uo_out[7:1]),
    //     .out(uo_out[0])
    //     );
    
endmodule
