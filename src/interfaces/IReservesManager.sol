// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IReservesManager {
    event StaticPriceSet(address indexed token, uint256 price);

    /// @notice Sets a static price for a token
    /// @dev Only callable by admin. Used for USD value calculations
    /// @param token The token address
    /// @param price The price
    function setStaticPrice(address token, uint256 price) external;

    /// @notice Checks if a token is supported
    /// @dev Returns true if the token is supported, false otherwise
    /// @param token The token address
    /// @return True if the token is supported, false otherwise
    function isTokenSupported(address token) external view returns (bool);

    /// @notice Gets the static price for a token
    /// @dev Returns the static price for a token
    /// @param token The token address
    /// @return The static price for a token
    function getStaticPrice(address token) external view returns (uint256);
}
