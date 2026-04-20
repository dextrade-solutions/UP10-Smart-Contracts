// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IKYCVerifier.sol";
import "../Errors.sol";

abstract contract WithKYCVerifier {
    IKYCVerifier public kycVerifier;

    constructor(address _kycVerifier) {
        _setKYCVerifier(_kycVerifier);
    }

    function _setKYCVerifier(address _kycVerifier) internal {
        if (_kycVerifier == address(0)) revert InvalidZeroAddress();
        kycVerifier = IKYCVerifier(_kycVerifier);
    }
}
