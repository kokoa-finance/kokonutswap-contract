// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IOracle {
    event Update(uint256 newPrice, uint256 timestamp);

    function update() external;

    function getPrice() external view returns (uint256 price, bool valid);
}
