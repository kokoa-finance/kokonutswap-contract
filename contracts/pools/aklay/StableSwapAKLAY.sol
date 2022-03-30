// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../KlayPool.sol";

contract StableSwapAKLAY is KlayPool(2) {
    function __StableSwapAKLAY_init(
        address[] memory _coins,
        address _poolToken,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) public initializer {
        __KlayPool_init(_coins, _poolToken, _initialA, _fee, _adminFee);
    }
}
