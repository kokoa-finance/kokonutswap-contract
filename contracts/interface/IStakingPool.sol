// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IStakingPool {
    event Stake(address indexed from, address indexed to, uint256 amount);
    event Unstake(address indexed from, address indexed to, uint256 amount);
    event Release(uint256 totalSupply, uint256 accRewardPerShare, uint256 lastAccClaimedAmountFromVesting);
    event ClaimReward(address indexed usr, uint256 amount);

    function balanceOf(address usr) external view returns (uint256 balance);

    function totalSupply() external view returns (uint256 amount);

    function token() external view returns (address token_);

    /// @notice stake token
    function stake(address to, uint256 amount) external;

    /// @notice unstake token
    function unstake(address to, uint256 amount) external;

    function claimableReward(address usr) external view returns (uint256 claimable);

    // @deprecated
    function claimReward(address usr) external;

    function claimUnstakedReward(address usr) external;
}
