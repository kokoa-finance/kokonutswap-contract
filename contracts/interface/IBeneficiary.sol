// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

interface IBeneficiary {
    struct AccountInfo {
        uint256 lastReleased;
        uint256 accClaimedAmount;
        uint256 allocPoint;
        bool init;
    }

    event LogAccountAddition(address account, uint256 allocPoint);
    event LogSetAccount(address account, uint256 allocPoint);
    event LogRemoveAccount(address account);
    event Withdraw(address to, uint256 amount);
    event Claim(address account, uint256 amount);

    function accountInfo(address account)
        external
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool
        );

    function claimableToken(address account) external view returns (uint256);

    function claimToken(address account) external;
}
