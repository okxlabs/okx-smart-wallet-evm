#!/usr/bin/env ts-node

/**
 * Check if our P256 signature values meet OpenZeppelin requirements
 */

// P256 curve constants from OpenZeppelin
const N = BigInt("0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551");
const HALF_N = BigInt("0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8");

// Our signature values
const TEST_SIG_R = BigInt("69168112246712056019096804394424995511318531682122239614170693638574376090387");
const TEST_SIG_S = BigInt("34805107460435319700917502899190091830635094980993797501739654162971595177431");

console.log("🔍 Checking P256 Signature Values Against OpenZeppelin Requirements");
console.log("===================================================================");
console.log("");

console.log("📊 P256 Curve Constants:");
console.log("N (curve order):", "0x" + N.toString(16));
console.log("HALF_N (N/2):", "0x" + HALF_N.toString(16));
console.log("");

console.log("🔢 Our Signature Values:");
console.log("R:", "0x" + TEST_SIG_R.toString(16));
console.log("S:", "0x" + TEST_SIG_S.toString(16));
console.log("");

console.log("✅ Validation Results:");

// Check R value: 0 < r < N
const rValid = TEST_SIG_R > 0n && TEST_SIG_R < N;
console.log("R value valid (0 < r < N):", rValid);
if (!rValid) {
    console.log("  ❌ R is out of range!");
}

// Check S value: 0 < s <= HALF_N (OpenZeppelin requirement)
const sValid = TEST_SIG_S > 0n && TEST_SIG_S <= HALF_N;
console.log("S value valid (0 < s <= HALF_N):", sValid);
if (!sValid) {
    console.log("  ❌ S value violates OpenZeppelin malleability protection!");
    console.log("  Expected: s <= HALF_N");
    console.log("  Actual s:", TEST_SIG_S.toString());
    console.log("  HALF_N:  ", HALF_N.toString());
    console.log("  Need to flip s = N - s");
    
    const flippedS = N - TEST_SIG_S;
    console.log("  Flipped S:", "0x" + flippedS.toString(16));
    console.log("  Flipped S decimal:", flippedS.toString());
    
    const flippedSValid = flippedS > 0n && flippedS <= HALF_N;
    console.log("  Flipped S valid:", flippedSValid);
}

console.log("");
console.log("🎯 Overall signature validity:", rValid && sValid);

if (!sValid) {
    console.log("");
    console.log("🔧 SOLUTION: Update signature with flipped S value:");
    console.log("uint256 internal constant TEST_SIG_S =", (N - TEST_SIG_S).toString() + ";");
}