// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Treasury.sol";

contract CSLPEYEKSDTreasury is Treasury {
    function __CSLPEYEKSDTreasury_init(address addressBook) public initializer {
        __Treasury_init(addressBook);
    }
}
