// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../library/kip/IKIP7Detailed.sol";

interface IAKlay is IKIP7Detailed {
    function applyFee() external;

    function stakeKlay(address to) external payable;

    function unstakeKlay(address to, uint256 amount) external;

    function pendingKlay(address usr) external view returns (uint256 completed, uint256 yet);

    function claimKlay(address usr) external;
}
