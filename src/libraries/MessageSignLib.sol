// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.29;

library MessageSignLib {
    /// @dev The type hash of the message
    bytes32 private constant MESSAGE_TYPEHASH =
        keccak256(
            "OKXSmartWalletMessage(bytes32 hash,uint48 validUntil,address walletImpl)"
        );

    /// @dev Hash the message
    /// @param _hash The hash of the message
    /// @param validUntil The valid until timestamp
    /// @param walletImpl The wallet implementation address
    /// @return The hash of the message
    function hash(
        bytes32 _hash,
        uint48 validUntil,
        address walletImpl
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(MESSAGE_TYPEHASH, _hash, validUntil, walletImpl)
            );
    }
}
