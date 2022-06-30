// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./library/kip/KIP7Extended.sol";

contract KokonutSwapToken is KIP7Extended {
    function __KokonutSwapToken_init(string memory _name, string memory _symbol) public initializer {
        __KIP7Extended_init(_name, _symbol, 18);
    }
}
