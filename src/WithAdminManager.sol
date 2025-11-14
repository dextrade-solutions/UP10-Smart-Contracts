// SPDX-License-Identifier: MIT 

interface IAdminManager {
    function isAdminAddress(address) external view returns (bool);
}

contract WithAdminManager {
    IAdminManager public adminManager;

    modifier onlyAdmin() {
        require(adminManager.isAdminAddress(msg.sender), "Not admin");
        _;
    }
}
