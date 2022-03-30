// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IPoolManager.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IStableSwap.sol";
import "../../interface/klayswap/IKlayswapFactory.sol";
import "../../interface/klayswap/IKlayswapExchange.sol";
import "../../library/kip/IKIP7.sol";
import "../../library/Pausable.sol";

contract KlayPoolManager is IPoolManager, AccessControl, Pausable {
    IAddressBook public addressBook;
    address public override pool;
    address[] public coins;

    function __KlayPoolManager_init(address addressBook_, address pool_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
        pool = pool_;
        coins = IStableSwap(pool).coinList();
    }

    /// @dev assume that all coins are converted to ksd in one path.
    function claimAdminFee() external override {
        address tokenTreasury = addressBook.getAddress(bytes32("KSDTreasury"));
        require(tokenTreasury == msg.sender, "KlayPoolManager::claimAdminFee: Invalid msg.sender");

        address ksd = addressBook.getAddress(bytes32("KSD"));
        address klayswap = addressBook.getAddress(bytes32("KlayswapFactory"));
        uint256 ksdBalance = IKIP7(ksd).balanceOf(address(this));

        // withdraw adminFees
        IStableSwap(pool).withdrawAdminFees(address(this));

        // exchange adminFees to KSD
        address[] memory path = new address[](0);
        for (uint256 i = 0; i < coins.length; i++) {
            if (coins[i] == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                if (address(this).balance > 0) {
                    IKlayswapFactory(klayswap).exchangeKlayPos{value: address(this).balance}(ksd, 1, path);
                }
            } else {
                uint256 tokenBalance = IKIP7(coins[i]).balanceOf(address(this));
                if (tokenBalance > 0) {
                    IKIP7(coins[i]).approve(klayswap, tokenBalance);
                    IKlayswapFactory(klayswap).exchangeKctPos(coins[i], tokenBalance, ksd, 1, path);
                }
            }
        }

        // transfer additional KSD amount to KSDTreasury contract
        uint256 updatedKsdBalance = IKIP7(ksd).balanceOf(address(this));
        if (updatedKsdBalance > ksdBalance) {
            IKIP7(ksd).transfer(tokenTreasury, updatedKsdBalance - ksdBalance);
        }
    }

    function claimableAdminFee() external view override returns (uint256) {
        address ksd = addressBook.getAddress(bytes32("KSD"));
        address klayswap = addressBook.getAddress(bytes32("KlayswapFactory"));
        uint256[] memory adminBalances = IStableSwap(pool).adminBalanceList();

        // claimable the other adminFees
        uint256 claimableAmount;
        address lp;
        for (uint256 i = 0; i < coins.length; i++) {
            if (adminBalances[i] == 0) {
                continue;
            }
            if (coins[i] == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
                lp = IKlayswapFactory(klayswap).tokenToPool(address(0), ksd);
                claimableAmount = claimableAmount + IKlayswapExchange(lp).estimatePos(address(0), adminBalances[i]);
            } else {
                lp = IKlayswapFactory(klayswap).tokenToPool(coins[i], ksd);
                claimableAmount = claimableAmount + IKlayswapExchange(lp).estimatePos(coins[i], adminBalances[i]);
            }
        }

        return claimableAmount;
    }

    receive() external payable {}
}
