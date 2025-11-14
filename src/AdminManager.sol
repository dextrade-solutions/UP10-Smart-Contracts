// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./WithAdminManager.sol";
import "./Ownable.sol";

contract AdminManager is IAdminManager, Ownable {
    mapping(address => bool) public isAdmin;

    constructor() {
        isAdmin[msg.sender] = true;
    }

    function addAdmin(address _admin) external onlyOwner {
        isAdmin[_admin] = true;
    }

    function removeAdmin(address _admin) external onlyOwner {
        isAdmin[_admin] = false;
    }

    function isAdminAddress(address _addr) external view returns (bool) {
        return isAdmin[_addr];
    }
}
