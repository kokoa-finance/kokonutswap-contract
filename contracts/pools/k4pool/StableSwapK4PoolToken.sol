// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../PoolToken.sol";

contract StableSwapK4PoolToken is PoolToken {
    function __StableSwapK4PoolToken_init(string memory _name, string memory _symbol) public initializer {
        __PoolToken_init(_name, _symbol, 18);
    }
}
