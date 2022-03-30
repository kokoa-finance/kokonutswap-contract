// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./interface/IAddressBook.sol";
import "./library/Pausable.sol";

contract AddressBook is Pausable, IAddressBook {
    mapping(bytes32 => address) public generalContract;
    mapping(bytes32 => mapping(bytes32 => address)) public typeContract;

    function __AddressBook_init() public initializer {
        __Pausable_init();
    }

    function config(bytes32 what, address data) external onlyAdmin {
        generalContract[what] = data;
    }

    function config(
        bytes32 key1,
        bytes32 key2,
        address data
    ) external onlyAdmin {
        typeContract[key1][key2] = data;
    }

    function getAddress(bytes32 key) external view override returns (address) {
        return generalContract[key];
    }

    function getAddresses(bytes32[] memory keyList) external view returns (address[] memory) {
        address[] memory result = new address[](keyList.length);
        for (uint256 i = 0; i < keyList.length; i++) {
            result[i] = generalContract[keyList[i]];
        }
        return result;
    }

    function getAddress(bytes32 key1, bytes32 key2) external view override returns (address) {
        return typeContract[key1][key2];
    }
}
