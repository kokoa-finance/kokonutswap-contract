// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./II4ISwapPool.sol";

interface IStableSwap is II4ISwapPool {
    event TokenExchange(address indexed buyer, uint256 soldId, uint256 tokensSold, uint256 boughtId, uint256 tokensBought, uint256 fee);
    event AddLiquidity(address indexed provider, uint256[] tokenAmounts, uint256[] fees, uint256 invariant, uint256 tokenSupply);
    event RemoveLiquidity(address indexed provider, uint256[] tokenAmounts, uint256[] fees, uint256 tokenSupply);
    event RemoveLiquidityOne(address indexed provider, uint256 poolTokenAmount, uint256[] tokenAmounts, uint256[] fees, uint256 tokenSupply);
    event RemoveLiquidityImbalance(address indexed provider, uint256[] tokenAmounts, uint256[] fees, uint256 invariant, uint256 tokenSupply);
    event CommitNewOwner(uint256 indexed deadline, address indexed owner);
    event CommitNewFee(uint256 indexed deadine, uint256 fee, uint256 adminFee);
    event NewFee(uint256 fee, uint256 adminFee);
    event RampA(uint256 oldA, uint256 newA, uint256 initialTime, uint256 futureTime);
    event StopRampA(uint256 A, uint256 t);

    function N_COINS() external view returns (uint256);

    function APrecise() external view returns (uint256);

    function getLpPrice(uint256 i) external view returns (uint256);

    function getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) external view returns (uint256);

    function getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function getDyUnderlyingWithoutFee(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function removeLiquidityImbalance(uint256[] memory amounts, uint256 maxBurnAmount) external returns (uint256);

    function rampA(uint256 _futureA, uint256 _futureTime) external;

    function stopRampA() external;

    function commitNewFee(uint256 newFee, uint256 newAdminFee) external;

    function applyNewFee() external;

    function transferOwnership(address newOwner) external;

    function applyTransferOwnership() external;

    function revertTransferOwnership() external;

    function adminBalances(uint256 i) external view returns (uint256);

    function adminBalanceList() external view returns (uint256[] memory balances_);

    function withdrawAdminFees(address recipient) external;

    function donateAdminFees() external;
}
