// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface ITreasury {
    event BondCreated(address usr, uint256 amount, uint256 createdAt, uint256 vestingPeriod, uint256 bondRecordIndex);
    event BondClaimed(address usr, uint256 claimedAmount, uint256 timestamp, uint256 bondRecordIndex);

    struct BondRecord {
        uint256 amount;
        uint256 claimedAmount;
        uint256 createdAt;
        uint256 vestingPeriod;
    }

    function getBondRecord(address usr, uint256 index) external view returns (BondRecord memory);

    function getBondRecordLength(address usr) external view returns (uint256);

    function creatableBondAmount() external view returns (uint256);

    function createBond(
        address usr,
        uint256 amount,
        uint256 vestingPeriod
    ) external;

    function claimBond(address usr) external;

    function pendingBond(address usr) external view returns (uint256 completed, uint256 yet);
}
