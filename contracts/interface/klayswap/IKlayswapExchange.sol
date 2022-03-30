// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../library/kip/IKIP7Detailed.sol";

interface IKlayswapExchange is IKIP7Detailed {
    function fee() external view returns (uint256);

    function getCurrentPool() external view returns (uint256, uint256);

    function addKctLiquidity(uint256 amountA, uint256 amountB) external;

    function estimatePos(address token, uint256 amount) external view returns (uint256);

    function estimateNeg(address token, uint256 amount) external view returns (uint256);

    function addKlayLiquidity(uint256 amount) external payable;

    function tokenA() external view returns (address);

    function tokenB() external view returns (address);

    function removeLiquidity(uint256 amount) external;

    function claimReward() external;

    function updateMiningIndex() external;

    function changeMiningRate(uint256 _mining) external;
}
