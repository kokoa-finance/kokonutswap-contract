// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IPoolManager.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IMetaPool.sol";
import "../../library/kip/IKIP7Detailed.sol";
import "../../library/Pausable.sol";
import "../../interface/IBasePool.sol";

contract MetaK4PoolManager is IPoolManager, Pausable {
    IAddressBook public addressBook;
    address public override pool;
    address[] public coins;

    function __MetaK4PoolManager_init(address addressBook_, address pool_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
        pool = pool_;
        address[] memory coins_ = IMetaPool(pool).coinList();
        coins = coins_;
        for (uint256 i = 0; i < coins_.length - 1; i++) {
            IKIP7(coins_[i]).approve(pool_, type(uint256).max);
        }
    }

    function claimAdminFee() external override {
        IMetaPool _pool = IMetaPool(pool);
        address tokenTreasury = addressBook.getAddress(bytes32("KSDTreasury"));
        require(tokenTreasury == msg.sender, "invalid msg.sender");

        address ksd = _getKSD();
        uint256 ksdBalance = _getThisTokenBalance(ksd);

        // withdraw adminFees
        _pool.withdrawAdminFees(address(this));

        // exchange adminFees to KSD
        address[] memory _coins = coins;
        uint256 MAX_COIN = _coins.length - 1;
        for (uint256 i = 0; i < MAX_COIN; i++) {
            _pool.exchange(i, MAX_COIN, _getThisTokenBalance(_coins[i]), 0);
        }
        IBasePool basePool = IBasePool(_pool.basePool());
        uint256 ksdIndex = basePool.coinIndex(ksd);
        basePool.removeLiquidityOneCoin(_getThisTokenBalance(_coins[MAX_COIN]), ksdIndex, 0);

        // transfer additional KSD amount to KSDTreasury contract
        uint256 updatedKsdBalance = _getThisTokenBalance(ksd);
        if (updatedKsdBalance > ksdBalance) {
            IKIP7(ksd).transfer(tokenTreasury, updatedKsdBalance - ksdBalance);
        }
    }

    function claimableAdminFee() external view override returns (uint256) {
        IMetaPool _pool = IMetaPool(pool);
        IBasePool basePool = IBasePool(_pool.basePool());
        uint256[] memory feeAmounts = _pool.adminBalanceList();

        address[] memory _coins = coins;
        uint256 MAX_COIN = _coins.length - 1;
        uint256 baseLpAmount = feeAmounts[MAX_COIN] + _getThisTokenBalance(_coins[MAX_COIN]);
        for (uint256 i = 0; i < MAX_COIN; i++) {
            uint256 amount = feeAmounts[i] + _getThisTokenBalance(_coins[i]);
            if (amount == 0) {
                continue;
            }
            baseLpAmount += _pool.getDy(i, MAX_COIN, amount);
        }
        if (baseLpAmount == 0) {
            return 0;
        }
        uint256 ksdIndex = basePool.coinIndex(_getKSD());
        return basePool.calcWithdrawOneCoin(baseLpAmount, ksdIndex);
    }

    function getPoolValue() external view override returns (uint256) {
        IMetaPool _pool = IMetaPool(pool);
        IBasePool basePool = IBasePool(_pool.basePool());
        uint256[] memory _amounts = _pool.balanceList();

        address[] memory _coins = coins;
        uint256 MAX_COIN = _coins.length - 1;
        uint256 baseLpAmount = _amounts[MAX_COIN];
        for (uint256 i = 0; i < MAX_COIN; i++) {
            uint256 decimal = IKIP7Detailed(_pool.coins(i)).decimals();
            baseLpAmount += (_pool.getPrice(i, MAX_COIN) * _amounts[i]) / 10**decimal;
        }
        if (baseLpAmount == 0) {
            return 0;
        }
        uint256 ksdIndex = basePool.coinIndex(_getKSD());
        uint256[] memory basePoolAssets = basePool.calcWithdraw(baseLpAmount);
        uint256 ksdValue;
        for (uint256 i = 0; i < basePoolAssets.length; i++) {
            if (i == ksdIndex) {
                ksdValue += basePoolAssets[i];
                continue;
            }
            uint256 decimal = IKIP7Detailed(basePool.coins(i)).decimals();
            ksdValue += (basePoolAssets[i] * basePool.getPrice(i, ksdIndex)) / 10**decimal;
        }
        return ksdValue;
    }

    function _getKSD() internal view returns (address) {
        return addressBook.getAddress("KSD");
    }

    function _getThisTokenBalance(address token) internal view returns (uint256) {
        return IKIP7(token).balanceOf(address(this));
    }
}
