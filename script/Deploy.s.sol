// script/Deploy.s.sol
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/IDOManager.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        // TODO: Add constructor arguments
        // new IDOManager(usdt, usdc, flx, kyc, reservesAdmin, adminManager);
        vm.stopBroadcast();
    }
}
