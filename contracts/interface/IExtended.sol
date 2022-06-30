// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IExtended {
    function pool() external view returns (address);

    function coinIndex(address coin) external view returns (uint256);

    function getPrice(uint256 i, uint256 j) external view returns (uint256);

    function addLiquidity(uint256[] calldata amounts, uint256 minMintAmount) external returns (uint256);

    function removeLiquidity(uint256 _amount, uint256[] calldata minAmounts) external returns (uint256[] memory);

    function calcWithdraw(uint256 _amount) external view returns (uint256[] memory);

    function removeLiquidityOneCoin(
        uint256 _tokenAmount,
        uint256 i,
        uint256 _minAmount
    ) external returns (uint256);

    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view returns (uint256);

    function calcTokenAmount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256);
}
