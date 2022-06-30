// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./BasePoolManager.sol";

contract KSDUSDKManager is BasePoolManager {
    function __KSDUSDKManager_init(address addressBook_, address pool_) public initializer {
        __BasePoolManager_init(addressBook_, pool_);
    }
}
