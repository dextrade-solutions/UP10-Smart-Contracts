// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "../interfaces/IKYCVerifier.sol";

abstract contract WithKYCVerifier {
    IKYCVerifier public kycVerifier;

    constructor(address _kycVerifier) {
        _setKYCVerifier(_kycVerifier);
    }

    function setKYCVerifier(address _kycVerifier) external virtual {
        _setKYCVerifier(_kycVerifier);
    }

    function _setKYCVerifier(address _kycVerifier) internal {
        kycVerifier = IKYCVerifier(_kycVerifier);
    }
}
