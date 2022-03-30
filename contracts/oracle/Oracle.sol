// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "../interface/IOracle.sol";
import "../interface/IAddressBook.sol";

abstract contract Oracle is Pausable, IOracle {
    IAddressBook public addressBook;
    uint256 internal price; // WAD
    bool internal valid;

    function __Oracle_init(address addressBook_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
    }

    function getPrice() external view virtual override returns (uint256, bool) {
        return (price, valid);
    }

    function clear() external onlyAdmin {
        valid = false;
    }
}
