// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "./TokenGateway.sol";

contract CSLPEYEKSDGateway is Pausable, TokenGateway {
    function __CSLPEYEKSDGateway_init(address addressBook) public initializer {
        __TokenGateway_init(addressBook);
    }

    function tokenType() public pure override returns (bytes32) {
        return "CSLPEYEKSD";
    }
}
