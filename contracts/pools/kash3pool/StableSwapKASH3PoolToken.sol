// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../PoolToken.sol";

contract StableSwapKASH3PoolToken is PoolToken {
    function __StableSwapKASH3PoolToken_init(string memory _name, string memory _symbol) public initializer {
        __PoolToken_init(_name, _symbol, 18);
    }
}
