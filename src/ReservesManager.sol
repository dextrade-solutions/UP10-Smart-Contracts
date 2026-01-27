// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./EmergencyWithdrawAdmin.sol";
import "./interfaces/IReservesManager.sol";
import "./Errors.sol";

abstract contract ReservesManager is IReservesManager, EmergencyWithdrawAdmin {
    using Math for uint256;
    using SafeERC20 for IERC20;

    address public reservesAdmin;

    // Stablecoin addresses
    address public immutable USDT;
    address public immutable USDC;
    address public immutable FLX;

    // Track stablecoins already withdrawn by reserves admin per IDO per token
    mapping(uint256 => mapping(address => uint256)) public stablecoinsWithdrawnInToken;

    // Track penalty fees collected per IDO per stablecoin
    mapping(uint256 => mapping(address => uint256)) public penaltyFeesCollected;

    // Track unsold tokens withdrawn per IDO
    mapping(uint256 => uint256) public unsoldTokensWithdrawn;

    // Track refunded tokens withdrawn per IDO
    mapping(uint256 => uint256) public refundedTokensWithdrawn;

    // Track penalty fees withdrawn per IDO per stablecoin
    mapping(uint256 => mapping(address => uint256)) public penaltyFeesWithdrawn;

    uint32 private constant HUNDRED_PERCENT = 10_000_000;

    constructor(address _usdt, address _usdc, address _flx) {
        require(_usdt != address(0) && _usdc != address(0), InvalidTokenAddress());

        USDT = _usdt;
        USDC = _usdc;
        FLX = _flx;
    }
}
