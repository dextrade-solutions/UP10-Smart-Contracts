// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./WithAdminManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AdminManager is IAdminManager, Ownable {
    mapping(address => bool) public isAdmin;

    constructor(address _initialOwner, address _initialAdmin) Ownable(_initialOwner) {
        _setAdmin(_initialAdmin, true);
    }

    /// @inheritdoc IAdminManager
    function addAdmin(address _admin) external onlyOwner {
        _setAdmin(_admin, true);
        emit AdminAdded(_admin);
    }

    /// @inheritdoc IAdminManager
    function removeAdmin(address _admin) external onlyOwner {
        _setAdmin(_admin, false);
        emit AdminRemoved(_admin);
    }

    /// @inheritdoc IAdminManager
    function isAdminAddress(address _addr) external view returns (bool) {
        return isAdmin[_addr];
    }

    function _setAdmin(address _admin, bool _status) internal {
        isAdmin[_admin] = _status;
    }
}
