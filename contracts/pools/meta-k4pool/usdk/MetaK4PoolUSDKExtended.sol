// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../MetaPoolExtended.sol";

contract MetaK4PoolUSDKExtended is MetaPoolExtended {
    constructor(address pool) MetaPoolExtended(IMetaPool(pool)) {}

    function __MetaK4PoolUSDKExtended_init() external initializer {
        __MetaPoolExtended_init();
    }
}
