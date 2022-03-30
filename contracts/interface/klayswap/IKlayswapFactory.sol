// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IKlayswapFactory {
    function tokenToPool(address tokenA, address tokenB) external view returns (address);

    function exchangeKctPos(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        address[] calldata path
    ) external;

    function exchangeKlayPos(
        address token,
        uint256 amount,
        address[] calldata path
    ) external payable;

    function createKctPool(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        uint256 fee
    ) external;

    function createKlayPool(
        address token,
        uint256 amount,
        uint256 fee
    ) external payable;
}
