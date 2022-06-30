// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../PoolToken.sol";

contract StableSwapKSDUSDKToken is PoolToken {
    function __StableSwapKSDUSDKToken_init(string memory _name, string memory _symbol) public initializer {
        __PoolToken_init(_name, _symbol, 18);
    }
}
