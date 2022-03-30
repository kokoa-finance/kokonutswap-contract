// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IKIP7Receiver {
    function onKIP7Received(
        address _operator,
        address _from,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bytes4);
}
