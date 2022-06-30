// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IPoolManager.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IStableSwap.sol";
import "../../interface/klayswap/IKlayswapFactory.sol";
import "../../interface/klayswap/IKlayswapExchange.sol";
import "../../library/kip/IKIP7.sol";
import "../../library/Pausable.sol";
import "../../interface/ICryptoSwap2Pool.sol";

contract KlayPoolManager is IPoolManager, AccessControl, Pausable {
    address private constant KLAY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ICryptoSwap2Pool public immutable KLAY_KSD;

    IAddressBook public addressBook;
    address public override pool;
    address[] public coins;

    constructor(address _KLAY_KSD) {
        KLAY_KSD = ICryptoSwap2Pool(_KLAY_KSD);
    }

    function __KlayPoolManager_init(address addressBook_, address pool_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
        pool = pool_;
        coins = IStableSwap(pool).coinList();
    }

    /// @dev assume that all coins are converted to ksd in one path.
    function claimAdminFee() external override {
        address tokenTreasury = addressBook.getAddress(bytes32("KSDTreasury"));
        require(tokenTreasury == msg.sender, "Invalid msg.sender");

        address ksd = addressBook.getAddress(bytes32("KSD"));
        uint256 ksdBalance = IKIP7(ksd).balanceOf(address(this));

        // withdraw adminFees
        IStableSwap(pool).withdrawAdminFees(address(this));

        // exchange adminFees to Klay
        uint256 klayIndex = IStableSwap(pool).coinIndex(KLAY_ADDRESS);
        for (uint256 i = 0; i < coins.length; i++) {
            if (i == klayIndex) {
                continue;
            } else {
                uint256 tokenBalance = IKIP7(coins[i]).balanceOf(address(this));
                if (tokenBalance > 0) {
                    IKIP7(coins[i]).approve(pool, tokenBalance);
                    IStableSwap(pool).exchange(i, klayIndex, tokenBalance, 0);
                }
            }
        }

        // exchange Klay to KSD
        uint256 klayBalance = address(this).balance;
        if (klayBalance > 0) {
            KLAY_KSD.exchange{value: klayBalance}(0, 1, klayBalance, 0);
        }

        // transfer additional KSD amount to KSDTreasury contract
        uint256 updatedKsdBalance = IKIP7(ksd).balanceOf(address(this));
        if (updatedKsdBalance > ksdBalance) {
            IKIP7(ksd).transfer(tokenTreasury, updatedKsdBalance - ksdBalance);
        }
    }

    function claimableAdminFee() external view override returns (uint256) {
        uint256[] memory adminBalances = IStableSwap(pool).adminBalanceList();

        // claimable the other adminFees
        uint256 klayAmount = address(this).balance;
        uint256 klayIndex = IStableSwap(pool).coinIndex(KLAY_ADDRESS);
        for (uint256 i = 0; i < coins.length; i++) {
            uint256 amount = adminBalances[i] + _getThisTokenBalance(coins[i]);
            if (amount == 0) {
                continue;
            }
            if (i == klayIndex) {
                klayAmount += amount;
            } else {
                klayAmount += IStableSwap(pool).getDy(i, klayIndex, amount);
            }
        }

        return KLAY_KSD.getDy(0, 1, klayAmount);
    }

    function getPoolValue() external view override returns (uint256) {
        uint256[] memory _balances = IStableSwap(pool).balanceList();

        // claimable the other adminFees
        uint256 klayAmount;
        uint256 klayIndex = IStableSwap(pool).coinIndex(KLAY_ADDRESS);
        for (uint256 i = 0; i < coins.length; i++) {
            if (_balances[i] == 0) {
                continue;
            }
            if (i == klayIndex) {
                klayAmount += _balances[i];
            } else {
                klayAmount += (IStableSwap(pool).getPrice(i, klayIndex) * _balances[i]) / 10**18;
            }
        }

        return (klayAmount * KLAY_KSD.getPrice(0, 1)) / 10**18;
    }

    receive() external payable {}

    function _getThisTokenBalance(address token) internal view returns (uint256) {
        if (token == KLAY_ADDRESS) {
            return address(this).balance;
        }
        return IKIP7(token).balanceOf(address(this));
    }
}
