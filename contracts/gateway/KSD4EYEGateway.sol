// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "./TokenGateway.sol";

contract KSD4EYEGateway is Pausable, TokenGateway {
    function __KSD4EYEGateway_init(address addressBook) public initializer {
        __TokenGateway_init(addressBook);
    }

    function tokenType() public pure override returns (bytes32) {
        return "KSD4EYE";
    }
}
