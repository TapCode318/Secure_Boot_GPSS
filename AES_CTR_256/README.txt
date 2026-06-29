AES Verilog Modules
===================

1. Overview
-----------

This folder contains Verilog source files for AES encryption, AES decryption, key expansion, AES round transformations, and an AES-256 CTR streaming wrapper.

The design includes two main usage paths:

1. Basic AES encryption/decryption modules
   - Supports AES-128, AES-192, and AES-256 through configurable Nk and Nr parameters.
   - Includes encryption, decryption, key expansion, SubBytes, ShiftRows, MixColumns, and inverse transformation modules.

2. AES-256 CTR streaming modules
   - Uses AES-256 encryption to generate a keystream from a counter block.
   - XORs the keystream with input data to produce output data.
   - Suitable for stream-style block processing where one 128-bit block can be accepted every clock cycle after the key is loaded.

This README only describes the AES-related modules in this folder.

2. Main Modules
---------------

2.1 aes256_ctr_stream.v
~~~~~~~~~~~~~~~~~~~~~~~

Top-level module for AES-256 in CTR mode.

Main function:

    data_out = data_in XOR AES_Encrypt_256(counter, key)

In CTR mode, the same operation can be used for encryption and decryption because the AES core only encrypts the counter to generate the keystream.

Important ports:

    clk             : System clock
    rst             : Active-high reset
    key_load        : Load AES-256 key into the pipeline core
    key_in[255:0]   : 256-bit AES key
    ctr_load        : Load initial counter value
    ctr_init[127:0] : Initial 128-bit counter block
    valid_in        : Input block valid signal
    data_in[127:0]  : Input data block
    last_in         : Marks the last input block
    keep_in[15:0]   : Byte-valid mask for the input block
    ready_in        : Input ready signal, currently always 1
    valid_out       : Output block valid signal
    data_out[127:0] : Output data block
    last_out        : Delayed last signal aligned with output data
    keep_out[15:0]  : Delayed keep mask aligned with output data
    ctr_dbg[127:0]  : Counter value used for AES input
    keystream_dbg   : AES-generated keystream

Design notes:

    - The internal AES pipeline latency is 15 clock cycles.
    - key_load should be asserted at least 1 clock cycle before the first valid_in.
    - ctr_init is loaded when ctr_load is asserted.
    - If ctr_load and valid_in are asserted in the same cycle, the first block uses ctr_init.
    - The counter increments by 1 for every valid input block.

2.2 aes256_pipeline_top.v
~~~~~~~~~~~~~~~~~~~~~~~~~

Pipelined AES-256 encryption core.

Main function:

    data_out = AES_Encrypt_256(data_in, key_in)

This module expands the 256-bit key into 15 round keys and performs AES-256 encryption with 14 rounds.

Parameters used internally:

    Nk = 8
    Nr = 14

Important ports:

    clk             : System clock
    rst             : Active-high reset
    key_load        : Load expanded round keys into internal register
    key_in[255:0]   : 256-bit AES key
    valid_in        : Input valid signal
    data_in[127:0]  : 128-bit plaintext/counter input block
    valid_out       : Output valid signal
    data_out[127:0] : 128-bit AES encrypted output block

Pipeline behavior:

    - Initial AddRoundKey stage
    - 13 normal AES rounds
    - 1 final AES round without MixColumns
    - valid_out is delayed through a 15-stage valid pipeline

2.3 aes256_round_enc.v
~~~~~~~~~~~~~~~~~~~~~~

AES normal encryption round.

Round structure:

    SubBytes -> ShiftRows -> MixColumns -> AddRoundKey

Used for rounds 1 to 13 in AES-256.

2.4 aes256_final_round_enc.v
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

AES final encryption round.

Final round structure:

    SubBytes -> ShiftRows -> AddRoundKey

MixColumns is not used in the final AES round.

2.5 KeyExpansion.v
~~~~~~~~~~~~~~~~~~

Generates AES round keys.

Supported configurations:

    AES-128: Nk = 4, Nr = 10
    AES-192: Nk = 6, Nr = 12
    AES-256: Nk = 8, Nr = 14

For AES-256, this module generates 15 round keys, each 128 bits wide.

2.6 AESEncrypt.v
~~~~~~~~~~~~~~~~

Sequential AES encryption module with configurable key size.

Supported modes:

    AESEncrypt #(4, 10)  -> AES-128
    AESEncrypt #(6, 12)  -> AES-192
    AESEncrypt #(8, 14)  -> AES-256

This module updates the AES state round by round when enable is asserted.

2.7 AESDecrypt.v
~~~~~~~~~~~~~~~~

Sequential AES decryption module with configurable key size.

Supported modes:

    AESDecrypt #(4, 10)  -> AES-128
    AESDecrypt #(6, 12)  -> AES-192
    AESDecrypt #(8, 14)  -> AES-256

This module uses inverse AES transformations:

    InvShiftRows
    InvSubBytes
    AddRoundKey
    InvMixColumns

2.8 AES.v
~~~~~~~~~

FPGA/demo top-level module for testing AES-128, AES-192, and AES-256 encryption/decryption.

It connects AES encrypt/decrypt modules with LED and seven-segment display outputs.

Selection input:

    sel = 00 -> AES-128
    sel = 01 -> AES-192
    sel = 10 or 11 -> AES-256

This module is mainly for demonstration and board-level visualization, not for the CTR stream datapath.

3. Supporting Modules
---------------------

The AES design uses the following transformation and helper modules:

    SubBytes.v          : AES S-box substitution
    SubTable.v          : AES S-box lookup table
    ShiftRows.v         : AES ShiftRows transformation
    MixColumns.v        : AES MixColumns transformation
    InvSubBytes.v       : AES inverse S-box substitution
    InvSubTable.v       : AES inverse S-box lookup table
    InvShiftRow.v       : AES inverse ShiftRows transformation
    InvMixColumns.v     : AES inverse MixColumns transformation
    Binary2BCD.v        : Binary to BCD converter for display demo
    DisplayDecoder.v    : Seven-segment display decoder

Required dependency:

    AddRoundKey.v       : XORs AES state with round key

Note: The uploaded source list instantiates AddRoundKey, but AddRoundKey.v was not included in the uploaded files. The project must include this module to compile successfully.

4. AES-CTR Operation
--------------------

For each 128-bit block i:

    keystream_i = AES_Encrypt_256(counter_i, key)
    data_out_i  = data_in_i XOR keystream_i
    counter_i   = counter_i + 1

If data_in is plaintext, data_out is ciphertext.
If data_in is ciphertext, data_out is plaintext.

The AES-CTR wrapper does not use AES decryption logic. Only AES encryption is needed because CTR mode encrypts the counter to create the keystream.

5. Testbenches
--------------

5.1 tb_aes256_pipeline_top.v
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Tests the raw AES-256 pipelined encryption core.

Example test vector:

    key       = 000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f
    plaintext = 00112233445566778899aabbccddeeff
    expected  = 8ea2b7ca516745bfeafc49904b496089

5.2 tb_aes256_ctr_stream.v
~~~~~~~~~~~~~~~~~~~~~~~~~~

Tests AES-256 CTR stream operation.

Example key and counter:

    key      = 603deb1015ca71be2b73aef0857d7781_1f352c073b6108d72d9810a30914dff4
    ctr_init = f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff

The testbench sends ciphertext blocks and prints plaintext output blocks.

6. Example Simulation
---------------------

Using ModelSim/QuestaSim:

    vlog SubTable.v SubBytes.v ShiftRows.v MixColumns.v AddRoundKey.v KeyExpansion.v \
         aes256_round_enc.v aes256_final_round_enc.v aes256_pipeline_top.v \
         aes256_ctr_stream.v tb_aes256_ctr_stream.v

    vsim tb_aes256_ctr_stream
    run -all

Using Vivado Simulator:

    1. Add all Verilog source files to the project.
    2. Set tb_aes256_ctr_stream or tb_aes256_pipeline_top as the simulation top.
    3. Run behavioral simulation.
    4. Check printed data_out values and waveform signals.

Useful waveform signals:

    clk
    rst
    key_load
    ctr_load
    valid_in
    data_in
    ctr_dbg
    keystream_dbg
    valid_out
    data_out
    last_out
    keep_out

7. File Structure
-----------------

Suggested AES folder structure:

    AES_CTR_256/
    |-- AES.v
    |-- AESEncrypt.v
    |-- AESDecrypt.v
    |-- KeyExpansion.v
    |-- AddRoundKey.v
    |-- SubBytes.v
    |-- SubTable.v
    |-- ShiftRows.v
    |-- MixColumns.v
    |-- InvSubBytes.v
    |-- InvSubTable.v
    |-- InvShiftRow.v
    |-- InvMixColumns.v
    |-- Binary2BCD.v
    |-- DisplayDecoder.v
    |-- aes256_round_enc.v
    |-- aes256_final_round_enc.v
    |-- aes256_pipeline_top.v
    |-- aes256_ctr_stream.v
    |-- tb_aes256_pipeline_top.v
    |-- tb_aes256_ctr_stream.v
    `-- README.txt

8. Notes and Limitations
------------------------

    - aes256_ctr_stream currently keeps ready_in permanently high.
    - There is no back-pressure handling on the output side.
    - The CTR counter is incremented as a 128-bit value.
    - key_load must be completed before valid input data is sent.
    - AES-CTR does not provide integrity or authenticity by itself.
    - The same key and counter pair must not be reused for different messages.
    - AddRoundKey.v must be present for successful compilation.

9. Recommended Top Modules
--------------------------

Use these top modules depending on the purpose:

    AES-256 CTR stream processing:
        aes256_ctr_stream

    Raw AES-256 block encryption:
        aes256_pipeline_top

    Basic AES encrypt/decrypt demo with LEDs and HEX display:
        AES

10. Author
----------

Developed as part of the AES hardware implementation project.
