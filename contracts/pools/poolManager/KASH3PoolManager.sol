// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./BasePoolManager.sol";

contract KASH3PoolManager is BasePoolManager {
    function __KASH3PoolManager_init(
        address addressBook_,
        address pool_,
        address[][] memory pathList
    ) public initializer {
        __BasePoolManager_init(addressBook_, pool_);
        uint256 _coinLength = coins.length;
        require(_coinLength == pathList.length);
        for (uint256 i = 0; i < _coinLength; i++) {
            _changePath(i, pathList[i]);
        }
    }
}
