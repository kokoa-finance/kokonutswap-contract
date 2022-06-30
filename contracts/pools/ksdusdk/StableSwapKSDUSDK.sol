// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../BasePool.sol";

contract StableSwapKSDUSDK is BasePool(2) {
    function __StableSwapKSDUSDK_init(
        address[] memory _coins,
        address _poolToken,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) public initializer {
        uint256[] memory _PRECISION_MUL = new uint256[](2);
        _PRECISION_MUL[0] = 1;
        _PRECISION_MUL[1] = 1;
        uint256[] memory _RATES = new uint256[](2);
        _RATES[0] = 1000000000000000000;
        _RATES[1] = 1000000000000000000;
        __BasePool_init(_coins, _PRECISION_MUL, _RATES, _poolToken, _initialA, _fee, _adminFee);
    }
}
