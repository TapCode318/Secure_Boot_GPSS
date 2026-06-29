SHA3-512 / Keccak Module
=======================

1. Overview
-----------

This folder contains the Verilog implementation of a Keccak-based SHA3-512 hashing core.

The design receives input data through a 32-bit streaming interface, pads the final message block, absorbs data into a 1600-bit Keccak state, runs the Keccak-f[1600] permutation, and produces a 512-bit hash output.

In the Secure Boot system, this module can be used to calculate the hash digest of firmware data after decryption. The digest can then be compared with an expected hash or used in the RSA signature verification flow.

This README only describes the SHA3/Keccak module files in this folder.

2. Main Function
----------------

The top-level module is:

    keccak.v

The core implements a SHA3-512-style flow:

    Input message
        |
        v
    32-bit stream input
        |
        v
    Padding
        |
        v
    576-bit rate block
        |
        v
    Keccak-f[1600] permutation
        |
        v
    512-bit hash output

The module uses:

- State size: 1600 bits
- Rate: 576 bits
- Capacity: 1024 bits
- Output length: 512 bits
- Padding suffix: 0x06
- Keccak-f permutation rounds: 24 rounds

3. Folder Structure
-------------------

The SHA3/Keccak folder contains the following files:

    f_permutation.v
        Controls the Keccak-f[1600] permutation process.
        It accepts a 576-bit padded input block, XORs it into the current
        1600-bit state, and runs the round function through 24 rounds.

    keccak.v
        Top-level SHA3-512 module.
        It connects the padder and f_permutation modules, handles byte
        reordering, receives 32-bit input words, and outputs a 512-bit digest.

    padder.v
        Pads the input message and groups data into 576-bit blocks.
        It receives 32-bit words and generates padded blocks for the
        permutation core.

    padder1.v
        Generates the padding pattern for the final incomplete 32-bit word.
        It inserts the SHA3 padding suffix 0x06 depending on byte_num.

    rconst.v
        Generates round constants for the Keccak iota step.

    round.v
        Implements one Keccak-f[1600] round.
        The round includes theta, rho, pi, chi, and iota steps.

4. Top Module Interface
-----------------------

Module:

    keccak(clk, reset, in, in_ready, is_last, byte_num, buffer_full, out, out_ready)

Ports:

    clk
        System clock.

    reset
        Reset signal. When asserted, internal state and control registers
        are cleared.

    in [31:0]
        32-bit input data word.

    in_ready
        Input valid signal from the user logic.
        When this signal is 1, the input word is considered valid if the
        internal buffer is not full.

    is_last
        Indicates that the current input word is the last word of the message.

    byte_num [1:0]
        Number of valid bytes in the final input word when is_last = 1.
        If is_last = 0, byte_num is ignored and the input word is treated
        as a full 4-byte word.

    buffer_full
        Output signal indicating that the internal 576-bit block buffer is full.
        The input side should wait when this signal is asserted.

    out [511:0]
        512-bit hash digest output.

    out_ready
        Output valid signal. When out_ready = 1, the 512-bit hash value is ready.

5. Input Protocol
-----------------

The input is sent as 32-bit words.

For normal input words:

    in_ready = 1
    is_last  = 0

For the final word:

    in_ready = 1
    is_last  = 1
    byte_num = number of valid bytes in the final word

Meaning of byte_num when is_last = 1:

    byte_num = 0
        No valid byte in the final word.
        Padding starts immediately.

    byte_num = 1
        Only in[31:24] is valid.

    byte_num = 2
        in[31:24] and in[23:16] are valid.

    byte_num = 3
        in[31:24], in[23:16], and in[15:8] are valid.

If is_last = 0, the module treats the input word as a full 32-bit word.

The input logic should only provide new data when the buffer is not full.

6. Padding Behavior
-------------------

The module uses SHA3-style padding with suffix 0x06.

In padder1.v, the final partial word is padded as follows:

    in = 0x11223344

    byte_num = 0 -> out = 0x06000000
    byte_num = 1 -> out = 0x11060000
    byte_num = 2 -> out = 0x11220600
    byte_num = 3 -> out = 0x11223306

The padder also sets the final padding bit at the end of the rate block.

7. Internal Architecture
------------------------

The internal architecture can be summarized as:

    keccak.v
        |
        |-- padder.v
        |       |
        |       |-- padder1.v
        |
        |-- f_permutation.v
                |
                |-- rconst.v
                |
                |-- round.v

The data path is:

    32-bit input word
        -> padder
        -> 576-bit padded block
        -> byte reorder
        -> f_permutation
        -> 1600-bit internal state
        -> top 512 bits selected
        -> byte reorder
        -> 512-bit digest output

8. Keccak Round Function
------------------------

The file round.v implements one Keccak-f[1600] round using the standard steps:

    theta
        Mixes columns of the 5x5 state array.

    rho
        Rotates each 64-bit lane by a fixed offset.

    pi
        Rearranges lane positions.

    chi
        Applies the nonlinear substitution step.

    iota
        XORs the round constant into lane A[0][0].

The f_permutation.v module repeatedly applies this round function for 24 rounds.

9. Output Behavior
------------------

After the final input block is padded and absorbed, the permutation core finishes the required rounds. When the hash is ready:

    out_ready = 1

At that time:

    out[511:0]

contains the 512-bit digest.

The output bytes are reordered in keccak.v before being exposed at the top-level output.

10. Example Simulation Flow
---------------------------

A simple testbench should perform the following steps:

1. Assert reset.
2. Deassert reset.
3. Send message words through in[31:0].
4. Assert in_ready for each valid input word.
5. Assert is_last on the final word.
6. Set byte_num according to the number of valid bytes in the final word.
7. Wait for out_ready.
8. Compare out with the expected SHA3-512 digest.

Example compile command using Icarus Verilog:

    iverilog -o sha3_tb \
        tb_sha3.v \
        keccak.v \
        padder.v \
        padder1.v \
        f_permutation.v \
        round.v \
        rconst.v

    vvp sha3_tb

Note: This folder currently contains the RTL modules. A separate testbench file is required for simulation.

11. Suggested Test Vectors
--------------------------

Recommended SHA3-512 test cases:

    Empty message:
        Input length = 0 bytes

    Short message:
        Input = "abc"

    Multi-word message:
        Input length > 4 bytes

    Multi-block message:
        Input length > 72 bytes

The SHA3-512 rate is 576 bits = 72 bytes, so messages longer than 72 bytes
should test multi-block absorption.

12. Design Notes
----------------

- The design processes input in 32-bit words.
- The internal Keccak rate block is 576 bits, equal to 18 input words.
- The output digest length is 512 bits.
- The design uses handshake signals such as in_ready, buffer_full, and out_ready.
- The byte reordering logic in keccak.v is important for correct digest formatting.
- The permutation state is stored in f_permutation.v as a 1600-bit register.
- round.v is combinational, while f_permutation.v controls the sequential round execution.

13. Limitations
---------------

- This module is configured for a 512-bit digest.
- It is not a general-purpose SHA3 module with selectable SHA3-224, SHA3-256, SHA3-384, and SHA3-512 modes.
- The current uploaded files do not include a testbench.
- Throughput is limited by the sequential 24-round permutation control.
- The input interface uses 32-bit words, so external logic must format byte streams correctly.

14. Possible Improvements
-------------------------

Possible future improvements include:

- Add a dedicated testbench with official SHA3-512 test vectors.
- Add a wrapper with start, done, valid, and ready signals for easier Secure Boot integration.
- Add support for continuous firmware streaming.
- Add FIFO buffering between AES decryption and SHA3 hashing.
- Add parameter support for SHA3-224, SHA3-256, SHA3-384, and SHA3-512.
- Add waveform documentation for in_ready, is_last, byte_num, buffer_full, out_ready, and out.
- Add synthesis and timing reports for FPGA implementation.

15. Project Context
-------------------

This SHA3-512 / Keccak module can be used as the hashing component in a Secure Boot system.

A typical Secure Boot data flow is:

    Encrypted firmware
        -> AES-CTR-256 decryption
        -> SHA3-512 hash calculation
        -> RSA signature verification
        -> boot pass / boot fail

In this flow, the SHA3-512 module is responsible for generating the firmware digest. The final boot decision should be made by the verification and control logic, not by the SHA3 module alone.

16. License Notice
------------------

The uploaded Verilog files contain the following copyright notice:

    Copyright 2013, Homer Hsing <homer.hsing@gmail.com>

The files are licensed under the Apache License, Version 2.0.

When reusing or modifying this RTL source code, keep the original copyright
and license notice in the source files.
