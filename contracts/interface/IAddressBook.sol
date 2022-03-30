// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IAddressBook {
    function getAddress(bytes32 key) external view returns (address);

    function getAddresses(bytes32[] memory keyList) external view returns (address[] memory);

    function getAddress(bytes32 key1, bytes32 key2) external view returns (address);
}
