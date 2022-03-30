// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface ITokenGateway {
    event Deposit(address usr, uint256 tokenAmount, uint256 refundAmount, uint256 createdBondAmount, uint256 createdBondValue, uint256 vestingPeriod);

    function discountRatio() external view returns (uint256);

    function deposit(uint256 amount) external returns (uint256 refundAmount);
}
