// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Ownable.sol";
    
contract KYCRegistry is Ownable {
    mapping(address => bool) public isVerified;

    function verify(address user) external onlyOwner {
        isVerified[user] = true;
    }

    function revoke(address user) external onlyOwner {
        isVerified[user] = false;
    }

    function isKYCed(address user) external view returns (bool) {
        return isVerified[user];
    }
}
