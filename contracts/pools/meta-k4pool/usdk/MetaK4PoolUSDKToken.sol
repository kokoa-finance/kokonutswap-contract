// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../PoolToken.sol";

contract MetaK4PoolUSDKToken is PoolToken {
    function __MetaK4PoolUSDKToken_init(string memory name_, string memory symbol_) public initializer {
        __PoolToken_init(name_, symbol_, 18);
    }
}
