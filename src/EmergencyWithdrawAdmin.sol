// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./admin_manager/WithAdminManager.sol";

abstract contract EmergencyWithdrawAdmin is WithAdminManager {
    using SafeERC20 for IERC20;

    modifier onlyEmergencyWithdrawAdmin() {
        require(adminManager.isSuperAdminAddress(msg.sender), "Only emergency withdraw admin");
        _;
    }

    function emergencyWithdraw(address _token, uint256 _amount) external onlyEmergencyWithdrawAdmin {
        require(_amount > 0, "Invalid amount");

        if (_token != address(0)) {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            payable(msg.sender).transfer(_amount);
        }
    }
}