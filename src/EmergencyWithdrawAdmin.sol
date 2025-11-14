// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IERC20.sol";

contract EmergencyWithdrawAdmin {
    address public emergencyWithdrawAdmin;

    modifier onlyEmergencyWithdrawAdmin() {
        require(msg.sender == emergencyWithdrawAdmin, "Only emergency withdraw admin");
        _;
    }

    function changeEmergencyWithdrawAdmin(
        address newAdmin
    ) external onlyEmergencyWithdrawAdmin {
        require(newAdmin != address(0), "Invalid address");
        emergencyWithdrawAdmin = newAdmin;
    }

    function emergencyWithdraw(address _token, uint256 _amount) external onlyEmergencyWithdrawAdmin {
        require(_amount > 0, "Invalid amount");

        if (_token != address(0)) {
            require(IERC20(_token).transfer(msg.sender, _amount), "Transfer failed");
        } else {
            payable(msg.sender).transfer(_amount);
        }
    }
}