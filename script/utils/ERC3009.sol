// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4);
}

/**
 * @title ERC-3009 Token
 * @notice EIP-3009: Transfer With Authorization
 * https://eips.ethereum.org/EIPS/eip-3009
 *
 * 核心功能：
 * - transferWithAuthorization: 持有者签名授权转账，第三方执行
 * - receiveWithAuthorization:  只允许 msg.sender == to 的转账
 * - cancelAuthorization:       取消未使用的授权
 */
contract ERC3009Token {

    // ─────────────────────────────────────────────────────────────
    //  ERC-20 Storage
    // ─────────────────────────────────────────────────────────────

    string  public name;
    string  public symbol;
    uint8   public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256)                     public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // ─────────────────────────────────────────────────────────────
    //  ERC-3009 Storage
    // ─────────────────────────────────────────────────────────────

    // authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    // ─────────────────────────────────────────────────────────────
    //  EIP-712
    // ─────────────────────────────────────────────────────────────

    bytes32 public DOMAIN_SEPARATOR;

    // keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH =
        0x7c7c6cdb67a18743f49ec6fa9b35f50d52ed05cbed4cc592e13b44501c1a2267;

    // keccak256("ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)")
    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH =
        0xd099cc98ef71107a616c4f0f941f04c322d8e254fe26b3c6668db87aae413de8;

    // keccak256("CancelAuthorization(address authorizer,bytes32 nonce)")
    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        0x158b0a9edf7a828aad02f63cd515c68ef2f50ba807396f6d12842833a1597429;

    // ─────────────────────────────────────────────────────────────
    //  Events
    // ─────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    // ─────────────────────────────────────────────────────────────
    //  Errors
    // ─────────────────────────────────────────────────────────────

    // ERC-1271
    bytes4 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    error InvalidSignature();
    error AuthorizationNotYetValid(uint256 validAfter, uint256 timestamp);
    error AuthorizationExpired(uint256 validBefore, uint256 timestamp);
    error AuthorizationAlreadyUsed(address authorizer, bytes32 nonce);
    error CallerMustBePayee(address caller, address to);
    error InsufficientBalance();
    error InsufficientAllowance();

    // ─────────────────────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────────────────────

    constructor() {
        name   = "ERC3009Token";
        symbol = "ERC3009";

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(name)),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));

        _mint(msg.sender, 1000E18);
    }

    // ─────────────────────────────────────────────────────────────
    //  ERC-20
    // ─────────────────────────────────────────────────────────────

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    // ─────────────────────────────────────────────────────────────
    //  ERC-3009: transferWithAuthorization
    //  任何人可以提交 from 的签名来执行转账
    // ─────────────────────────────────────────────────────────────

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        _requireValidAuthorization(from, nonce, validAfter, validBefore);

        bytes32 digest = _buildDigest(
            TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
            from, to, value, validAfter, validBefore, nonce
        );
        _requireValidSignature(from, digest, v, r, s);

        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    // ─────────────────────────────────────────────────────────────
    //  ERC-3009: receiveWithAuthorization
    //  只允许 msg.sender == to，防止前置交易攻击
    // ─────────────────────────────────────────────────────────────

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        if (msg.sender != to) revert CallerMustBePayee(msg.sender, to);

        _requireValidAuthorization(from, nonce, validAfter, validBefore);

        bytes32 digest = _buildDigest(
            RECEIVE_WITH_AUTHORIZATION_TYPEHASH,
            from, to, value, validAfter, validBefore, nonce
        );
        _requireValidSignature(from, digest, v, r, s);

        _markAuthorizationUsed(from, nonce);
        _transfer(from, to, value);
    }

    // ─────────────────────────────────────────────────────────────
    //  ERC-3009: cancelAuthorization
    //  授权者可以取消未使用的 nonce
    // ─────────────────────────────────────────────────────────────

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8   v,
        bytes32 r,
        bytes32 s
    ) external {
        if (authorizationState[authorizer][nonce]) {
            revert AuthorizationAlreadyUsed(authorizer, nonce);
        }

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                CANCEL_AUTHORIZATION_TYPEHASH,
                authorizer,
                nonce
            ))
        ));
        _requireValidSignature(authorizer, digest, v, r, s);

        authorizationState[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    // ─────────────────────────────────────────────────────────────
    //  Internal Helpers
    // ─────────────────────────────────────────────────────────────

    function _transfer(address from, address to, uint256 value) internal {
        if (balanceOf[from] < value) revert InsufficientBalance();
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to]   += value;
        }
        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply     += value;
        balanceOf[to]   += value;
        emit Transfer(address(0), to, value);
    }

    function _buildDigest(
        bytes32 typehash,
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                typehash,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            ))
        ));
    }

    function _requireValidAuthorization(
        address authorizer,
        bytes32 nonce,
        uint256 validAfter,
        uint256 validBefore
    ) internal view {
        if (block.timestamp <= validAfter)
            revert AuthorizationNotYetValid(validAfter, block.timestamp);
        if (block.timestamp >= validBefore)
            revert AuthorizationExpired(validBefore, block.timestamp);
        if (authorizationState[authorizer][nonce])
            revert AuthorizationAlreadyUsed(authorizer, nonce);
    }

    function _requireValidSignature(
        address signer,
        bytes32 digest,
        uint8 v, bytes32 r, bytes32 s
    ) internal view {
        if (_isContract(signer)) {
            // ERC-1271: 合约钱包签名验证
            bytes memory sig = abi.encodePacked(r, s, v);
            try IERC1271(signer).isValidSignature(digest, sig) returns (bytes4 magic) {
                if (magic != _ERC1271_MAGIC_VALUE) revert InvalidSignature();
            } catch {
                revert InvalidSignature();
            }
        } else {
            // EOA: ecrecover 验证
            address recovered = ecrecover(digest, v, r, s);
            if (recovered == address(0) || recovered != signer)
                revert InvalidSignature();
        }
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function _markAuthorizationUsed(address authorizer, bytes32 nonce) internal {
        authorizationState[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }
}