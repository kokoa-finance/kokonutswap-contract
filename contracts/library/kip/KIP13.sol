// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./IKIP13.sol";
import "../openzeppelin/proxy/Initializable.sol";

contract KIP13 is Initializable, IKIP13 {
    bytes4 private constant _INTERFACE_ID_KIP13 = 0x01ffc9a7;
    mapping(bytes4 => bool) private _supportedInterfaces;

    function __KIP13_init() internal initializer {
        _registerInterface(_INTERFACE_ID_KIP13);
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return _supportedInterfaces[interfaceId];
    }

    function _registerInterface(bytes4 interfaceId) internal {
        require(interfaceId != 0xffffffff, "KIP13::_registerInterface: invalid interface id");
        _supportedInterfaces[interfaceId] = true;
    }
}
