// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IDistributionTreasury {
    function addSubTreasury(address treasury) external;

    function updateClaimAmountByAddresses(address[] calldata _subTreasuries) external returns (uint256);

    function updateClaimAmount() external returns (uint256);

    function claimableAmount() external view returns (uint256); //accClaimedAmount

    function accClaimedToken() external view returns (uint256);

    function distribute(address to, uint256 amount) external;
}
