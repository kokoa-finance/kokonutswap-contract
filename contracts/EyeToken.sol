// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./library/kip/KIP7Extended.sol";

contract EyeToken is KIP7Extended {
    function __EyeToken_init(string memory _name, string memory _symbol) public initializer {
        __KIP7Extended_init(_name, _symbol, 18);
    }
}
