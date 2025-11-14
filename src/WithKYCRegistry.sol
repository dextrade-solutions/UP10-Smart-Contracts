// SPDX-License-Identifier: MIT 

interface IKYCRegistry {
    function isKYCed(address user) external view returns (bool);
}

contract WithKYCRegistry {
    IKYCRegistry public kyc;

    modifier onlyKYC() {
        require(kyc.isKYCed(msg.sender), "KYC required");
        _;
    }
}