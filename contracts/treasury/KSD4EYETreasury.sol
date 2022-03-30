// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Treasury.sol";

contract KSD4EYETreasury is Treasury {
    function __KSD4EYETreasury_init(address addressBook) public initializer {
        __Treasury_init(addressBook);
    }
}
