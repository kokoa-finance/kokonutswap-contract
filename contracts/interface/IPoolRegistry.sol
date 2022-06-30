// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IPoolRegistry {
    struct PoolInfo {
        uint128 index;
        uint64 nCoins;
        uint64 poolType; // 1: BASE_POOL, 2: META_POOL, 3: CRYPTO_POOL
        uint256 decimals;
        address[] coins;
        string name;
    }

    function getPoolFromLpToken(address lpToken) external view returns (address);

    function getLpToken(address pool) external view returns (address);

    function getPoolManager(address pool) external view returns (address);

    function getStakingPool(address pool) external view returns (address);

    function getDecimals(address pool) external view returns (uint256[] memory);

    function getPoolInfo(address _pool) external view returns (PoolInfo memory);

    function getPoolList() external view returns (address[] memory);
}
