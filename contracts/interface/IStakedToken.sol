// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/kip/IKIP7Detailed.sol";

interface IStakedToken is IKIP7Detailed {
    event Stake(address indexed user, address to, uint256 amount, uint256 liquidityIndex);
    event Unstake(address indexed user, address to, uint256 amount, uint256 liquidityIndex);
    event InstantUnstake(address indexed user, address to, uint256 amount, uint256 liquidityIndex);
    event Claim(address usr, uint256 amount);
    event Earn(uint256 now, uint256 amount, uint256 liquidityIndex);
    event UpdateAirdrop(address token, uint256 totalSupply, uint256 accRewardPerShare, uint256 lastVestedAmount);
    event ClaimAirdropToken(address token, address usr, uint256 amount);

    struct UnstakeRecord {
        uint256 timestamp;
        uint256 amount;
    }

    struct AirdropInfo {
        address treasury;
        uint256 accRewardPerShare;
        uint256 lastVestedAmount;
    }

    function unstakeCount(address user) external view returns (uint256);

    function claimCount(address user) external view returns (uint256);

    function unstakeRecord(address user, uint256 index) external view returns (UnstakeRecord memory);

    function lockUpPeriod() external view returns (uint256);

    function liquidityIndex() external view returns (uint256);

    function rawBalanceOf(address usr) external view returns (uint256);

    function rawTotalSupply() external view returns (uint256);

    function stake(address to, uint256 amount) external;

    function unstake(address to, uint256 amount) external;

    function instantUnstake(address to, uint256 amount) external;

    function claim(address account) external;

    function earn(uint256 amount) external;
}
