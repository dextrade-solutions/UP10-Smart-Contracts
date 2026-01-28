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

    // Nonce per user to prevent replay
    mapping(address => uint256) public nonces;

    // EIP-712 typehash for KYC
    bytes32 private constant KYC_TYPEHASH =
        keccak256("KYC(address user,uint256 expires,uint256 nonce)");

    constructor(address _kycSigner) EIP712("KYCVerifier", "1.0") Ownable(msg.sender) {
        require(_kycSigner != address(0), "Invalid signer");
        kycSigner = _kycSigner;
    }

    /// @notice Update the trusted KYC signer
    /// @param _kycSigner New signer address
    function setKYCSigner(address _kycSigner) external onlyOwner {
        require(_kycSigner != address(0), "Invalid signer");

        address previousSigner = kycSigner;
        kycSigner = _kycSigner;

        emit KYCSignerUpdated(previousSigner, _kycSigner);
    }

    /// @notice Verify KYC signature and mark action allowed
    /// @param expires Timestamp after which signature is invalid
    /// @param signature Signed data from KYC authority
    function verifyKYC(uint256 expires, bytes calldata signature) external {
        require(block.timestamp <= expires, "KYC expired");

        uint256 nonce = nonces[msg.sender];

        bytes32 structHash = keccak256(
            abi.encode(
                KYC_TYPEHASH,
                msg.sender,
                expires,
                nonce
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(digest, signature);

        require(signer == kycSigner, "Invalid KYC signature");

        // Increment nonce to prevent replay
        nonces[msg.sender]++;

        emit KYCVerified(msg.sender, expires);
    }
}
