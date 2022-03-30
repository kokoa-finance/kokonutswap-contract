// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * @title TokenVesting
 */
interface ITokenVesting {
    event TokensReleased(uint256 amount);

    /**
     * @return address of token contract.
     */
    function token() external view returns (address);

    /**
     * @return address of rewardManger who receives token.
     */
    function beneficiary() external view returns (address);

    /**
     * @return the total amount to vest.
     */
    function totalVestingAmount() external view returns (uint256);

    /**
     * @return the start time of the token vesting.
     */
    function start() external view returns (uint256);

    /**
     * @return the duration of the token vesting.
     */
    function duration() external view returns (uint256);

    /**
     * @return the amount of the token released.
     */
    function released() external view returns (uint256);

    /**
     * @return the amount of the token released.
     */
    function releasableAmount() external view returns (uint256);

    /**
     * @notice Transfers vested tokens.
     */
    function release() external;
}
