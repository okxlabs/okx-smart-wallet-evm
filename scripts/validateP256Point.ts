#!/usr/bin/env ts-node

/**
 * Validate P256 public key point and signature components
 */

// P256 curve constants from OpenZeppelin
const P = BigInt("0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF");
const A = BigInt("0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC");
const B = BigInt("0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B");
const N = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
const HALF_N = BigInt("0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8");

// Our values (latest from direct signing)
const TEST_PUBKEY_X = BigInt("93395446812770925679792685583480163168908246531166147805311304577982810709820");
const TEST_PUBKEY_Y = BigInt("5843431828147496338686936499235924335955323008009359491787085654138424314798");
const TEST_SIG_R = BigInt("83255797424987618116732354766739697622161832619357734191113277997916141776334");
const TEST_SIG_S = BigInt("28588369149912576761221137292854164820522886823326892316104512821385661729611");

console.log("🔍 P256 Point and Signature Validation");
console.log("=====================================");
console.log("");

function modPow(base: bigint, exponent: bigint, modulus: bigint): bigint {
    let result = 1n;
    base = base % modulus;
    while (exponent > 0n) {
        if (exponent % 2n === 1n) {
            result = (result * base) % modulus;
        }
        exponent = exponent >> 1n;
        base = (base * base) % modulus;
    }
    return result;
}

console.log("📊 Curve Parameters:");
console.log("P (field size):", "0x" + P.toString(16));
console.log("A:", "0x" + A.toString(16)); 
console.log("B:", "0x" + B.toString(16));
console.log("N (order):", "0x" + N.toString(16));
console.log("");

console.log("🔑 Public Key:");
console.log("X:", "0x" + TEST_PUBKEY_X.toString(16));
console.log("Y:", "0x" + TEST_PUBKEY_Y.toString(16));
console.log("");

// Check if point is on curve: y² = x³ + ax + b (mod p)
console.log("✅ Point Validation:");

// Check x and y are in field
const xInField = TEST_PUBKEY_X >= 0n && TEST_PUBKEY_X < P;
const yInField = TEST_PUBKEY_Y >= 0n && TEST_PUBKEY_Y < P;
console.log("X in field (0 <= x < P):", xInField);
console.log("Y in field (0 <= y < P):", yInField);

if (xInField && yInField) {
    // Calculate y²
    const y_squared = (TEST_PUBKEY_Y * TEST_PUBKEY_Y) % P;
    
    // Calculate x³ + ax + b
    const x_cubed = (TEST_PUBKEY_X * TEST_PUBKEY_X * TEST_PUBKEY_X) % P;
    const ax = (A * TEST_PUBKEY_X) % P;
    const rhs = (x_cubed + ax + B) % P;
    
    const onCurve = y_squared === rhs;
    console.log("Point on curve (y² = x³ + ax + b):", onCurve);
    
    if (!onCurve) {
        console.log("  y² =", "0x" + y_squared.toString(16));
        console.log("  x³ + ax + b =", "0x" + rhs.toString(16));
    }
} else {
    console.log("❌ Point coordinates out of field range!");
}

console.log("");
console.log("🔏 Signature Values:");
console.log("R:", "0x" + TEST_SIG_R.toString(16));
console.log("S:", "0x" + TEST_SIG_S.toString(16));

// Validate signature values
const rValid = TEST_SIG_R > 0n && TEST_SIG_R < N;
const sValid = TEST_SIG_S > 0n && TEST_SIG_S <= HALF_N;

console.log("R valid (0 < r < N):", rValid);
console.log("S valid (0 < s <= HALF_N):", sValid);

console.log("");
console.log("🎯 Overall Validation:");
console.log("Public key valid:", xInField && yInField && "Point on curve check above");
console.log("Signature valid:", rValid && sValid);