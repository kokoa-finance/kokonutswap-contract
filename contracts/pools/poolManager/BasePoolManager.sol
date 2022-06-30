// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IPoolManager.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IStableSwap.sol";
import "../../library/kip/IKIP7Detailed.sol";
import "../../library/Pausable.sol";

contract BasePoolManager is IPoolManager, Pausable {
    IAddressBook public addressBook;
    address public override pool;
    address[] public coins;
    mapping(uint256 => address[]) internal _path; // [initial token, pool, token, pool, token, ...]

    function __BasePoolManager_init(address addressBook_, address pool_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
        pool = pool_;
        coins = IStableSwap(pool).coinList();
    }

    function changePath(uint256 i, address[] memory path_) public onlyOwner {
        _changePath(i, path_);
    }

    function _changePath(uint256 i, address[] memory path_) internal {
        uint256 length = path_.length;
        require(length % 2 == 1, "Invalid path length");
        require(path_[0] == coins[i], "should start with coin itself");
        address ksd = _getKSD();
        require(path_[length - 1] == ksd, "last token should be ksd");
        for (uint256 j = 0; j < length - 1; j += 2) {
            IKIP7(path_[j]).approve(path_[j + 1], type(uint256).max);
        }
        _path[i] = path_;
    }

    function claimAdminFee() external override {
        address tokenTreasury = addressBook.getAddress(bytes32("KSDTreasury"));
        require(tokenTreasury == msg.sender, "Invalid msg.sender");

        address ksd = _getKSD();
        uint256 ksdBalance = _getThisTokenBalance(ksd);

        // withdraw adminFees
        IStableSwap(pool).withdrawAdminFees(address(this));

        // exchange adminFees to KSD
        address[] memory _coins = coins;
        for (uint256 i = 0; i < _coins.length; i++) {
            address[] memory _swapPath = _path[i];
            uint256 swapAmount = _getThisTokenBalance(_swapPath[0]);
            if (swapAmount == 0) {
                continue;
            }
            for (uint256 j = 0; j < _swapPath.length - 1; j += 2) {
                IStableSwap swapPool = IStableSwap(_swapPath[j + 1]);
                uint256 xIndex = swapPool.coinIndex(_swapPath[j]);
                uint256 yIndex = swapPool.coinIndex(_swapPath[j + 2]);
                swapAmount = swapPool.exchange(xIndex, yIndex, swapAmount, 0);
            }
        }

        // transfer additional KSD amount to KSDTreasury contract
        uint256 updatedKsdBalance = _getThisTokenBalance(ksd);
        if (updatedKsdBalance > ksdBalance) {
            IKIP7(ksd).transfer(tokenTreasury, updatedKsdBalance - ksdBalance);
        }
    }

    function claimableAdminFee() external view override returns (uint256) {
        IStableSwap _pool = IStableSwap(pool);
        uint256[] memory feeAmounts = _pool.adminBalanceList();

        address[] memory _coins = coins;
        uint256 ksdAmount;
        for (uint256 i = 0; i < _coins.length; i++) {
            address[] memory _swapPath = _path[i];
            uint256 swapAmount = feeAmounts[i] + _getThisTokenBalance(_coins[i]);
            if (swapAmount == 0) {
                continue;
            }
            for (uint256 j = 0; j < _swapPath.length - 1; j += 2) {
                IStableSwap swapPool = IStableSwap(_swapPath[j + 1]);
                uint256 xIndex = swapPool.coinIndex(_swapPath[j]);
                uint256 yIndex = swapPool.coinIndex(_swapPath[j + 2]);
                swapAmount = swapPool.getDy(xIndex, yIndex, swapAmount);
            }
            ksdAmount += swapAmount;
        }
        return ksdAmount;
    }

    function getPoolValue() external view override returns (uint256) {
        IStableSwap _pool = IStableSwap(pool);
        uint256[] memory _amounts = _pool.balanceList();

        address[] memory _coins = coins;
        uint256 ksdValue;
        for (uint256 i = 0; i < _coins.length; i++) {
            address[] memory _swapPath = _path[i];
            uint256 amount = _amounts[i];
            if (amount == 0) {
                continue;
            }
            uint256 price = 10**18;
            for (uint256 j = 0; j < _swapPath.length - 1; j += 2) {
                IStableSwap swapPool = IStableSwap(_swapPath[j + 1]);
                uint256 xIndex = swapPool.coinIndex(_swapPath[j]);
                uint256 yIndex = swapPool.coinIndex(_swapPath[j + 2]);
                price = (price * swapPool.getPrice(xIndex, yIndex)) / 10**18;
            }
            uint256 decimal = IKIP7Detailed(_coins[i]).decimals();
            ksdValue += (amount * price) / 10**decimal;
        }
        return ksdValue;
    }

    function getPathList() external view returns (address[][] memory) {
        uint256 length = coins.length;
        address[][] memory pathList = new address[][](length);
        for (uint256 i = 0; i < length; i++) {
            pathList[i] = _path[i];
        }
        return pathList;
    }

    function _getKSD() internal view returns (address) {
        return addressBook.getAddress(bytes32("KSD"));
    }

    function _getThisTokenBalance(address token) internal view returns (uint256) {
        return IKIP7(token).balanceOf(address(this));
    }
}
