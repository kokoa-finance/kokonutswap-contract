// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface II4ISwapPool {
    function balances(uint256 i) external view returns (uint256);

    function token() external view returns (address);

    function coins(uint256 i) external view returns (address);

    function getPrice(uint256 i, uint256 j) external view returns (uint256);

    function getVirtualPrice() external view returns (uint256);

    function A() external view returns (uint256);

    function fee() external view returns (uint256);

    function adminFee() external view returns (uint256);

    function coinIndex(address coin) external view returns (uint256);

    function coinList() external view returns (address[] memory coins_);

    function balanceList() external view returns (uint256[] memory balances_);

    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount) external payable returns (uint256);

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external payable returns (uint256);

    function removeLiquidity(uint256 _amount, uint256[] memory minAmounts) external returns (uint256[] memory);

    function removeLiquidityOneCoin(
        uint256 tokenAmount,
        uint256 i,
        uint256 minAmount
    ) external returns (uint256);

    function getDy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function getDyWithoutFee(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view returns (uint256);

    function calcTokenAmount(uint256[] memory amounts, bool isDeposit) external view returns (uint256);

    function calcWithdraw(uint256 _amount) external view returns (uint256[] memory);

    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view returns (uint256);

    function calcWithdrawOneCoinWithoutFee(uint256 _tokenAmount, uint256 i) external view returns (uint256);

    function withdrawLostToken(
        address _token,
        uint256 _amount,
        address _to
    ) external;
}
