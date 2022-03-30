// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "./TokenStakingPool.sol";

contract CSLPEYEKSDStakingPool is TokenStakingPool {
    constructor(address ADDRESS_BOOK_) TokenStakingPool(ADDRESS_BOOK_) {}

    function __CSLPEYEKSDStakingPool_init(address token_) public initializer {
        __TokenStakingPool_init(token_);
    }

    function beneficiary() public view override returns (IBeneficiary) {
        return IBeneficiary(ADDRESS_BOOK.getAddress("governBeneficiary"));
    }
}
