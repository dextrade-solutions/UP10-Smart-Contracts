// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ReservesManager {
    address public reservesAdmin;

    modifier onlyReservesAdmin() {
        require(msg.sender == reservesAdmin, "Only reserves admin");
        _;
    }

    constructor(address _initialAdmin) {
        reservesAdmin = _initialAdmin;
    }

    function changeReservesAdmin(
        address newAdmin
    ) external onlyReservesAdmin {
        _setReservesAdmin(newAdmin);
    }

    // TODO make only available to withdraw stables after users claim
    // TODO for vested tokens admin can only withdraw (1) Excess tokens that are not sold, including refunded ones 
    // TODO and (2) Tokens that are taken as refund penalty

    function adminWithdraw(address _token, uint256 _amount) external onlyReservesAdmin {
        require(_amount > 0, "Invalid amount");

        if (_token != address(0)) {
            require(IERC20(_token).transfer(msg.sender, _amount), "Transfer failed");
        } else {
            payable(msg.sender).transfer(_amount);
        }
    }

    function _setReservesAdmin(address _newAdmin) internal {
        require(_newAdmin != address(0), "Invalid address");
        reservesAdmin = _newAdmin;
        // TODO emit event
    }
}