// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./IBasePool.sol";

interface IMetaPool is IBasePool {
    function basePool() external view returns (address);

    function exchangeUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external returns (uint256);

    event TokenExchangeUnderlying(address indexed buyer, uint256 soldId, uint256 tokensSold, uint256 boughtId, uint256 tokensBought, uint256 fee);
}
