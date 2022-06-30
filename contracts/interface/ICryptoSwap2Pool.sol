// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./II4ISwapPool.sol";

interface ICryptoSwap2Pool is II4ISwapPool {
    function exchangeExtended(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy,
        address sender,
        address receiver,
        bytes32 cb
    ) external payable returns (uint256);

    function lpPrice() external view returns (uint256);

    function gamma() external view returns (uint256);

    function midFee() external view returns (uint256);

    function outFee() external view returns (uint256);

    function priceOracle() external view returns (uint256);

    function claimableAdminFee() external view returns (uint256);

    function claimAdminFee() external;
}
