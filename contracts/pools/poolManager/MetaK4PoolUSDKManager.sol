// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./MetaK4PoolManager.sol";

contract MetaK4PoolUSDKManager is MetaK4PoolManager {
    function __MetaK4PoolUSDKManager_init(address addressBook_, address pool_) public initializer {
        __MetaK4PoolManager_init(addressBook_, pool_);
    }
}
