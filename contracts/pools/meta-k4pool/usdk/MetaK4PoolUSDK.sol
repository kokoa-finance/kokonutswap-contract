// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../MetaPool.sol";

contract MetaK4PoolUSDK is MetaPool(2, 4) {
    function __MetaK4PoolUSDK_init(
        address[] memory _coins,
        uint256[] memory _PRECISION_MUL,
        uint256[] memory _RATES,
        address _poolToken,
        address _basePool,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) external initializer {
        __MetaPool_init(_coins, _PRECISION_MUL, _RATES, _poolToken, _basePool, _initialA, _fee, _adminFee);
    }
}
