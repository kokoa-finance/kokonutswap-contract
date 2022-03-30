// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IPoolManager.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IStableSwap.sol";
import "../../library/kip/IKIP7.sol";
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
        require(length % 2 == 1, "BasePoolManager::changePath: Invalid path length");
        require(path_[0] == coins[i], "BasePoolManager::changePath: should start with coin itself");
        address ksd = addressBook.getAddress(bytes32("KSD"));
        require(path_[length - 1] == ksd, "BasePoolManager::changePath: last token should be ksd");
        for (uint256 j = 0; j < length - 1; j += 2) {
            IKIP7(path_[j]).approve(path_[j + 1], type(uint256).max);
        }
        _path[i] = path_;
    }

    function claimAdminFee() external override {
        address tokenTreasury = addressBook.getAddress(bytes32("KSDTreasury"));
        require(tokenTreasury == msg.sender, "BasePoolManager::claimAdminFee: Invalid msg.sender");

        address ksd = addressBook.getAddress(bytes32("KSD"));
        uint256 ksdBalance = IKIP7(ksd).balanceOf(address(this));

        // withdraw adminFees
        IStableSwap(pool).withdrawAdminFees(address(this));

        // exchange adminFees to KSD
        address[] memory _coins = coins;
        for (uint256 i = 0; i < _coins.length; i++) {
            address[] memory _swapPath = _path[i];
            uint256 swapAmount = IKIP7(_swapPath[0]).balanceOf(address(this));
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
        uint256 updatedKsdBalance = IKIP7(ksd).balanceOf(address(this));
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
            uint256 swapAmount = feeAmounts[i];
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

    function getPathList() external view returns (address[][] memory) {
        uint256 length = coins.length;
        address[][] memory pathList = new address[][](length);
        for (uint256 i = 0; i < length; i++) {
            pathList[i] = _path[i];
        }
        return pathList;
    }
}
