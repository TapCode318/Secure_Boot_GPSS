from Crypto.Cipher import AES
from Crypto.PublicKey import RSA
from Crypto.Util.number import bytes_to_long, long_to_bytes
from hashlib import sha3_512
from pathlib import Path

PLAINTEXT = b"dai hoc cong nghe thong tin ho chi minh"

AES_KEY = bytes.fromhex(
    "11223344112233441122334411223344"
    "11223344112233441122334411223344"
)

IV = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff")

FW_SIZE = len(PLAINTEXT)
FW_OFFSET = 0x58
SIG_OFFSET = 0x18
SIG_WORDS = 0x40

MANIFEST_WORDS = 24

key_path = Path("vendor_rsa2048_private.pem")

if key_path.exists():
    rsa_key = RSA.import_key(key_path.read_bytes())
else:
    rsa_key = RSA.generate(2048, e=65537)
    key_path.write_bytes(rsa_key.export_key("PEM"))

n = rsa_key.n
d = rsa_key.d

# AES-CTR encrypt firmware
cipher = AES.new(AES_KEY, AES.MODE_CTR, nonce=b"", initial_value=int.from_bytes(IV, "big"))
ciphertext = cipher.encrypt(PLAINTEXT)

pad_len = ((len(ciphertext) + 15) // 16) * 16 - len(ciphertext)
ciphertext_padded = ciphertext + bytes(pad_len)

# Firmware plaintext hash for SEC expected_hash.
# SEC register order is reversed by 32-bit words.
fw_digest = sha3_512(PLAINTEXT).digest()
fw_digest_words = [fw_digest[i:i+4] for i in range(0, 64, 4)]
fw_digest_reg_order = b"".join(reversed(fw_digest_words))

words = []

# FW[0..3]
words += [
    0x53424346,  # "SBCF"
    0x00000001, # manifest version
    FW_SIZE,
    FW_OFFSET,
]

# FW[4..7] IV
for i in range(0, 16, 4):
    words.append(int.from_bytes(IV[i:i+4], "big"))

# FW[8..23] expected_hash in SEC register order
for i in range(0, 64, 4):
    words.append(int.from_bytes(fw_digest_reg_order[i:i+4], "big"))

assert len(words) == MANIFEST_WORDS

# Manifest bytes = FW[0..23], big-endian per word
manifest_bytes = b"".join(w.to_bytes(4, "big") for w in words)
manifest_hash = sha3_512(manifest_bytes).digest()

# PKCS#1 v1.5 DigestInfo for SHA3-512, no NULL parameters.
# DER:
# 30 4f
#    30 0b
#       06 09 60 86 48 01 65 03 04 02 0a
#    04 40 <64-byte digest>
SHA3_512_DIGESTINFO_PREFIX = bytes.fromhex(
    "304f300b060960864801650304020a0440"
)

digest_info = SHA3_512_DIGESTINFO_PREFIX + manifest_hash

em_len = 256
ps_len = em_len - len(digest_info) - 3

if ps_len < 8:
    raise RuntimeError("PKCS#1 v1.5 PS too short")

EM = b"\x00\x01" + (b"\xff" * ps_len) + b"\x00" + digest_info

m = bytes_to_long(EM)

if m >= n:
    raise RuntimeError("Encoded message >= RSA modulus. Regenerate RSA key.")

sig = pow(m, d, n)
sig_bytes = long_to_bytes(sig, 256)

# FW[24..87] signature, 64 words
for i in range(0, 256, 4):
    words.append(int.from_bytes(sig_bytes[i:i+4], "big"))

assert len(words) == FW_OFFSET

# FW[88..] ciphertext
for i in range(0, len(ciphertext_padded), 4):
    words.append(int.from_bytes(ciphertext_padded[i:i+4], "big"))

Path("firmware_cipher.hex").write_text(
    "\n".join(f"{w:08x}" for w in words) + "\n"
)

Path("rsa_public_key.vh").write_text(
    "`ifndef RSA_PUBLIC_KEY_VH\n"
    "`define RSA_PUBLIC_KEY_VH\n\n"
    f"`define RSA_PUBLIC_N 2048'h{n:0512x}\n\n"
    "`endif\n"
)

print("Generated firmware_cipher.hex")
print("Generated rsa_public_key.vh")
print("Firmware size:", FW_SIZE)
print("FW offset:", FW_OFFSET)
print("Signature offset:", SIG_OFFSET)
print("Signature words:", SIG_WORDS)
print("Manifest words:", MANIFEST_WORDS)
print("Ciphertext:", ciphertext.hex())
print("FW expected_hash register-order:", fw_digest_reg_order.hex())
print("Manifest hash:", manifest_hash.hex())
print("PKCS#1 v1.5 EM:", EM.hex())