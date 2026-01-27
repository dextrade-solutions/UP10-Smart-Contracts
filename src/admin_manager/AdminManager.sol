// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./WithAdminManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AdminManager is IAdminManager, Ownable {
    mapping(address => bool) public isAdmin;

    // Single super admin
    address public superAdmin;

    constructor(
        address _initialOwner,
        address _initialAdmin,
        address _initialSuperAdmin
    ) Ownable(_initialOwner) {
        _setAdmin(_initialAdmin, true);
        _setSuperAdmin(_initialSuperAdmin);
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

    /// @inheritdoc IAdminManager
    function isSuperAdminAddress(address _addr) external view returns (bool) {
        return superAdmin == _addr;
    }

    /// @inheritdoc IAdminManager
    function setSuperAdmin(address _newSuperAdmin) external onlyOwner {
        require(_newSuperAdmin != address(0), "Super admin cannot be zero address");
        address previous = superAdmin;
        _setSuperAdmin(_newSuperAdmin);
        emit SuperAdminChanged(previous, _newSuperAdmin);
    }

    // ---------------- Internal ----------------

    function _setAdmin(address _admin, bool _status) internal {
        isAdmin[_admin] = _status;
    }

    function _setSuperAdmin(address _newSuperAdmin) internal {
        superAdmin = _newSuperAdmin;
    }
}
