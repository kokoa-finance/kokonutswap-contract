// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IKlayswapUtils {
    function getPendingReward(address lp, address user)
        external
        view
        returns (
            uint256 kspReward,
            uint256 airdropCount,
            address[] memory airdropTokens,
            uint256[] memory airdropRewards
        );
}
