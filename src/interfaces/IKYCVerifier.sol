// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IKYCVerifier {
    event KYCVerified(address indexed user, uint256 expires);
    event KYCSignerUpdated(address indexed previousSigner, address indexed newSigner);

    /// @notice Verify KYC signature and mark action allowed
    /// @param expires Timestamp after which signature is invalid
    /// @param signature Signed data from KYC authority
    function verifyKYC(uint256 expires, bytes calldata signature) external;

    /// @notice Get the trusted KYC signer address
    function kycSigner() external view returns (address);

    /// @notice Get the nonce for a user
    /// @param user The address of the user
    function nonces(address user) external view returns (uint256);

    /// @notice Update the trusted KYC signer
    /// @param _kycSigner New signer address
    function setKYCSigner(address _kycSigner) external;
}
