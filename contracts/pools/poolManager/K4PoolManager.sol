// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./BasePoolManager.sol";

contract K4PoolManager is BasePoolManager {
    function __K4PoolManager_init(address addressBook_, address pool_) public initializer {
        __BasePoolManager_init(addressBook_, pool_);
    }
}
