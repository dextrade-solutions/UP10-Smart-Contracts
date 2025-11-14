// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EmergencyWithdrawAdmin {
    address public emergencyWithdrawAdmin;

    modifier onlyEmergencyWithdrawAdmin() {
        require(msg.sender == emergencyWithdrawAdmin, "Only emergency withdraw admin");
        _;
    }

    constructor(address _initialAdmin) {
        emergencyWithdrawAdmin = _initialAdmin;
    }

    function changeEmergencyWithdrawAdmin(
        address newAdmin
    ) external onlyEmergencyWithdrawAdmin {
        _setEmergencyWithdrawAdmin(newAdmin);
    }

    function emergencyWithdraw(address _token, uint256 _amount) external onlyEmergencyWithdrawAdmin {
        require(_amount > 0, "Invalid amount");

        if (_token != address(0)) {
            require(IERC20(_token).transfer(msg.sender, _amount), "Transfer failed");
        } else {
            payable(msg.sender).transfer(_amount);
        }
    }

    function _setEmergencyWithdrawAdmin(address _newAdmin) internal {
        require(_newAdmin != address(0), "Invalid address");
        emergencyWithdrawAdmin = _newAdmin;
    }
}