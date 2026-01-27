// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IAdminManager {
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);

    /// @notice Checks if an address has admin privileges
    /// @dev Returns the admin status from the isAdmin mapping
    /// @param _addr The address to check for admin privileges
    /// @return True if the address is an admin, false otherwise
    function isAdminAddress(address _addr) external view returns (bool);

    /// @notice Grants super admin privileges to an address
    /// @dev Sets the super admin
    /// @param _addr The address to be set as super admin
    function setSuperAdmin(address _addr) external;

    /// @notice Checks if an address has super admin privileges
    /// @dev Returns the super admin status from the superAdmin variable
    /// @param _addr The address to check for super admin privileges
    /// @return True if the address is a super admin, false otherwise
    function isSuperAdminAddress(address _addr) external view returns (bool);

    /// @notice Grants admin privileges to an address
    /// @dev Only callable by owner. Sets the address's admin status to true
    /// @param _admin The address to grant admin privileges
    function addAdmin(address _admin) external;

    /// @notice Revokes admin privileges from an address
    /// @dev Only callable by owner. Sets the address's admin status to false
    /// @param _admin The address to revoke admin privileges from
    function removeAdmin(address _admin) external;

    /// @notice Emitted when the super admin is changed
    /// @param previousSuperAdmin The address of the previous super admin
    /// @param newSuperAdmin The address of the new super admin
    event SuperAdminChanged(address indexed previousSuperAdmin, address indexed newSuperAdmin);
}