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

    struct TokenConfig {
        address token;
        uint256 price;
    }

    // Track penalty fees collected per IDO per stablecoin
    mapping(uint256 => mapping(address => uint256)) public penaltyFeesCollected;

    mapping(address => uint256) public staticPrices;
    mapping(address => bool) public enabledTokens;
    address[] public SUPPORTED_TOKENS;

    uint32 private constant HUNDRED_PERCENT = 10_000_000;

    constructor(TokenConfig[] memory tokens) {
        uint256 len = tokens.length;
        address[] memory supported = new address[](len);

        for (uint256 i; i < len; ) {
            address token = tokens[i].token;

            if (token == address(0)) revert ZeroAddress();
            if (enabledTokens[token]) revert DuplicateToken();

            staticPrices[token] = tokens[i].price;
            enabledTokens[token] = true;
            supported[i] = token;

            unchecked { ++i; }
        }

        SUPPORTED_TOKENS = supported;
    }

    function getSupportedTokensWithPrices() external view returns (TokenConfig[] memory) {
        TokenConfig[] memory tokens = new TokenConfig[](SUPPORTED_TOKENS.length);

        for (uint256 i; i < SUPPORTED_TOKENS.length; ) {
            tokens[i] = TokenConfig({
                token: SUPPORTED_TOKENS[i],
                price: staticPrices[SUPPORTED_TOKENS[i]]
            });

            unchecked { ++i; }
        }

        return (tokens);
    }

    /// @inheritdoc IReservesManager
    function isTokenSupported(address token) public view returns (bool) {
        return enabledTokens[token];
    }

    /// @inheritdoc IReservesManager
    function setStaticPrice(address token, uint256 price) external onlyAdmin {
        if (!enabledTokens[token]) revert InvalidToken();
        staticPrices[token] = price;
        emit StaticPriceSet(token, price);
    }

    /// @inheritdoc IReservesManager
    function getStaticPrice(address token) public view returns (uint256) {
        return staticPrices[token];
    }
}
