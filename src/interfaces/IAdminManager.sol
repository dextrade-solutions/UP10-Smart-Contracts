// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAdminManager {
    function isAdminAddress(address) external view returns (bool);

    function addAdmin(address _admin) external;
    
    function removeAdmin(address _admin) external;
}