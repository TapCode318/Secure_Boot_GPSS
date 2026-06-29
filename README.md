AES_CTR_256 Module
==================

1. Overview
-----------

This folder contains the implementation of the AES-CTR-256 module used in the Secure Boot system.

AES-CTR-256 is used to decrypt encrypted firmware before the firmware is verified and booted. The module applies AES with a 256-bit key in Counter (CTR) mode. In CTR mode, AES encryption is applied to a counter value to generate a keystream, then the keystream is XORed with ciphertext to recover plaintext.

In this Secure Boot project, AES-CTR-256 helps protect firmware confidentiality. The firmware stored in external memory is encrypted, and only the secure boot hardware can decrypt it using the correct key and counter configuration.

2. Role in Secure Boot
----------------------

The AES_CTR_256 module is part of the firmware loading and verification flow:

    Encrypted Firmware
            |
            v
    AES-CTR-256 Decryption
            |
            v
    Plain Firmware
            |
            v
    SHA3-512 Hash Calculation
            |
            v
    RSA Signature Verification
            |
            v
    Boot Pass / Boot Fail

The AES module does not decide whether the firmware is valid. Its main responsibility is to decrypt firmware blocks. The decrypted data is then passed to the hashing and verification stages.

3. AES-CTR-256 Principle
------------------------

For each 128-bit data block:

    keystream_i = AES_Encrypt_256(counter_i, key)
    plaintext_i = ciphertext_i XOR keystream_i
    counter_i   = counter_i + 1

Because CTR mode uses AES encryption for both encryption and decryption, the same AES core can be used to recover plaintext from ciphertext.

4. Main Features
----------------

- AES with 256-bit key
- CTR mode operation
- 128-bit block processing
- Counter-based keystream generation
- Suitable for firmware decryption in secure boot
- Can be integrated with SHA3-512 and RSA verification modules
- Hardware-oriented RTL implementation

5. Input and Output Description
-------------------------------

Typical signals used in this module include:

    clk             : System clock
    rst_n           : Active-low reset
    start           : Start signal for AES-CTR operation
    key             : 256-bit AES key
    counter         : Initial counter / nonce value
    ciphertext      : 128-bit encrypted input block
    plaintext       : 128-bit decrypted output block
    done            : Indicates that the current block has been processed

Depending on the actual RTL implementation, signal names may be different. Please check the top module for exact port names.

6. Folder Structure
-------------------

This folder may contain files such as:

    AES_CTR_256/
    ├── aes_ctr_256.v              : Top module for AES-CTR-256
    ├── aes_core.v                 : AES encryption core
    ├── key_expansion_256.v        : AES-256 key expansion logic
    ├── sub_bytes.v                : AES SubBytes transformation
    ├── shift_rows.v               : AES ShiftRows transformation
    ├── mix_columns.v              : AES MixColumns transformation
    ├── add_round_key.v            : AES AddRoundKey transformation
    ├── tb_aes_ctr_256.v           : Testbench for simulation
    └── README.txt                 : Module documentation

Note: The actual file names may be different depending on the implementation.

7. Simulation
-------------

To verify the AES-CTR-256 module, run the provided testbench using a Verilog simulator such as Vivado, ModelSim, QuestaSim, or Icarus Verilog.

Example using Icarus Verilog:

    iverilog -o aes_ctr_tb tb_aes_ctr_256.v aes_ctr_256.v aes_core.v
    vvp aes_ctr_tb

The testbench should check:

- Correct AES-256 encryption result
- Correct CTR counter increment
- Correct XOR between keystream and ciphertext
- Correct plaintext output
- Correct done signal behavior

8. Expected Behavior
--------------------

When start is asserted:

1. The module receives a 256-bit key, an initial counter value, and a 128-bit ciphertext block.
2. The AES core encrypts the counter value using the 256-bit key.
3. The generated keystream is XORed with the ciphertext.
4. The plaintext block is produced at the output.
5. The done signal is asserted when the block is complete.
6. For the next block, the counter is incremented.

9. Design Notes
---------------

- AES-CTR does not require AES decryption logic.
- Each block can be processed independently after the counter value is known.
- The counter must not be reused with the same key for different firmware images.
- In a complete secure boot system, AES only provides confidentiality. Integrity and authenticity must still be checked using SHA3-512 and RSA verification.
- For better throughput, this module can be connected to a FIFO so that AES decryption and SHA3 hashing can run in a pipeline.

10. Security Considerations
---------------------------

- The AES key should be stored securely and must not be exposed through normal firmware access.
- The counter or nonce value must be unique for each encrypted firmware image.
- Reusing the same key and counter pair can weaken CTR-mode security.
- AES-CTR alone does not detect modified ciphertext. Therefore, decrypted firmware must always be verified by hash and signature checking before booting.

11. Future Improvements
-----------------------

Possible improvements include:

- Adding FIFO buffering between AES and SHA3 modules
- Supporting multi-block firmware streaming
- Adding valid/ready handshake signals
- Optimizing AES round implementation for higher throughput
- Adding more test vectors for different firmware blocks
- Adding waveform documentation for start, done, counter, ciphertext, keystream, and plaintext signals

12. Project Context
-------------------

This AES_CTR_256 module belongs to the Secure Boot system for a GNSS/GPS-related embedded platform. The complete system aims to protect firmware using:

- AES-CTR-256 for firmware confidentiality
- SHA3-512 for firmware integrity checking
- RSA verification for firmware authenticity
- Secure Boot control logic for boot pass / boot fail decision

13. Author
----------

Developed as part of the Secure Boot project.

Repository:
https://github.com/TapCode318/Secure_Boot_GPSS
