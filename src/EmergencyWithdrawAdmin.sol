// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./admin_manager/WithAdminManager.sol";

abstract contract EmergencyWithdrawAdmin is WithAdminManager {
    using SafeERC20 for IERC20;

    event EmergencyWithdraw(address indexed token, address indexed recipient, uint256 amount);

    modifier onlyEmergencyWithdrawAdmin() {
        if (!adminManager.isSuperAdminAddress(msg.sender)) revert CallerNotSuperAdmin();
        _;
    }

    function emergencyWithdraw(address _token, uint256 _amount) external onlyEmergencyWithdrawAdmin {
        if (_amount == 0) revert InvalidAmount();

        if (_token != address(0)) {
            IERC20(_token).safeTransfer(msg.sender, _amount);
        } else {
            (bool success, ) = payable(msg.sender).call{value: _amount}("");
            if (!success) revert ETHTransferFailed();
        }

        emit EmergencyWithdraw(_token, msg.sender, _amount);
    }
}