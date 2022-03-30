// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./IKIP7.sol";
import "./IKIP7Detailed.sol";
import "./IKIP13.sol";

interface IKIP7Extended is IKIP7Detailed {
    function mint(address usr, uint256 amount) external returns (bool);

    function burn(address usr, uint256 amount) external returns (bool);
}
