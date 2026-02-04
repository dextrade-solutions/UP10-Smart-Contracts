// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "../interfaces/IKYCVerifier.sol";

contract KYCVerifier is IKYCVerifier, EIP712, Ownable {
    using ECDSA for bytes32;

    // Trusted KYC signer
    address public kycSigner;

    // Nonce per (user, caller) to prevent replay and to avoid mempool griefing across callers
    mapping(address => mapping(address => uint256)) public nonces;

    // EIP-712 typehash for KYC
    bytes32 private constant KYC_TYPEHASH =
        keccak256("KYC(address user,address caller,uint256 expires,uint256 nonce)");

    constructor(address _kycSigner) EIP712("KYCVerifier", "1.0") Ownable(msg.sender) {
        if (_kycSigner == address(0)) revert InvalidSigner();
        kycSigner = _kycSigner;
    }

    /// @notice Update the trusted KYC signer
    /// @param _kycSigner New signer address
    function setKYCSigner(address _kycSigner) external onlyOwner {
        if (_kycSigner == address(0)) revert InvalidSigner();

        address previousSigner = kycSigner;
        kycSigner = _kycSigner;

        emit KYCSignerUpdated(previousSigner, _kycSigner);
    }

    /// @notice Verify KYC signature and mark action allowed
    /// @param user User to be validated
    /// @param expires Timestamp after which signature is invalid
    /// @param signature Signed data from KYC authority
    function verifyKYC(address user, uint256 expires, bytes calldata signature) external {
        if (block.timestamp > expires) revert KYCExpired();

        address caller = msg.sender;

        uint256 nonce = nonces[user][caller];

        bytes32 structHash = keccak256(
            abi.encode(
                KYC_TYPEHASH,
                user,
                caller,
                expires,
                nonce
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        if (signer != kycSigner) revert InvalidKYCSignature();

        // Increment nonce to prevent replay
        nonces[user][caller]++;

        emit KYCVerified(user, expires);
    }
}
