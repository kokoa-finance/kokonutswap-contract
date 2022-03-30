// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./IKIP13.sol";

interface IKIP7 is IKIP13 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function safeTransfer(
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external;

    function safeTransfer(address recipient, uint256 amount) external;

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount,
        bytes calldata data
    ) external;

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external;
}
