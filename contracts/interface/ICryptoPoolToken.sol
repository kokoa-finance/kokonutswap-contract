// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./IPoolToken.sol";

interface ICryptoPoolToken is IPoolToken {
    function mintRelative(address _to, uint256 frac) external returns (uint256);
}
