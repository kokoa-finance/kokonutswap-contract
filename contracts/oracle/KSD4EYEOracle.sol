// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Oracle.sol";
import "../interface/IBasePool.sol";

contract KSD4EYEOracle is Oracle {
    bytes32 public constant tokenType = "KSD4EYE";

    function __KSD4EYEOracle_init(address addressBook) public initializer {
        __Oracle_init(addressBook);
    }

    function update() external override {}

    function getPrice() external view override returns (uint256, bool) {
        IBasePool pool = IBasePool(addressBook.getAddress(tokenType, "swap"));
        return (pool.getVirtualPrice(), true);
    }
}
