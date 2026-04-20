// script/Deploy.s.sol
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/IDOManager.sol";
import "../src/admin_manager/AdminManager.sol";
import "../src/kyc/KYCVerifier.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        // new KYCVerifier(0xb40758cFfd3ba2A59be8F72a12C47B6Ca08a9aCc);
        // TODO: Add constructor arguments
        // new IDOManager(new ReservesManager.TokenConfig[](0), 0xb40758cFfd3ba2A59be8F72a12C47B6Ca08a9aCc, 0x6b3dFa2999655bF86c090Ef5E19128F1c5a9aF4C);
        // new AdminManager(0x21eD7B2F0ff8697dd8acd123C2D778A2cb5E45CF, 0xe23016De6198aB8b7A2EF8E9fcbeD6704efC7f5B, 0xe23016De6198aB8b7A2EF8E9fcbeD6704efC7f5B);
        // new AdminManager(0x21eD7B2F0ff8697dd8acd123C2D778A2cb5E45CF, 0x91B7075BF5163b073F71a571b0B4BDEFde141E99, 0x91B7075BF5163b073F71a571b0B4BDEFde141E99);
        vm.stopBroadcast();
    }
}
