// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IPoolManager {
    function pool() external view returns (address);

    function claimAdminFee() external;

    function claimableAdminFee() external view returns (uint256);

    function getPoolValue() external view returns (uint256);
}
