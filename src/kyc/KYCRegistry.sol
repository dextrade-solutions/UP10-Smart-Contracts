// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IKYCRegistry.sol";

contract KYCRegistry is IKYCRegistry, Ownable {
    mapping(address => bool) public isVerified;

    constructor(address _initialOwner) Ownable(_initialOwner) {}

    /// @inheritdoc IKYCRegistry
    function verify(address user) external onlyOwner {
        isVerified[user] = true;
        emit UserVerified(user);
    }

    /// @inheritdoc IKYCRegistry
    function revoke(address user) external onlyOwner {
        isVerified[user] = false;
        emit UserRevoked(user);
    }

    /// @inheritdoc IKYCRegistry
    function isKYCed(address user) external view returns (bool) {
        return isVerified[user];
    }
}
