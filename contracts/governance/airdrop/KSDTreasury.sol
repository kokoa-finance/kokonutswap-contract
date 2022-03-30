// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../interface/IDistributionTreasury.sol";
import "../../interface/IAddressBook.sol";
import "../../interface/IPoolManager.sol";
import "../../library/kip/IKIP7.sol";
import "../../library/Pausable.sol";

contract KSDTreasury is IDistributionTreasury, Pausable {
    IAddressBook public addressBook;
    uint256 public override accClaimedToken;
    address public token;
    address[] internal _subTreasuryList;

    function __KSDTreasury_init(address addressBook_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
        token = addressBook.getAddress(bytes32("KSD"));
    }

    function addSubTreasury(address treasury) external onlyOwner {
        address[] memory treasuries = _subTreasuryList;
        for (uint256 i = 0; i < treasuries.length; i++) {
            require(treasuries[i] != treasury, "KSDTreasury::addSubTreasury: already registered");
        }
        _subTreasuryList.push(treasury);
    }

    function removeSubTreasury(address treasury) external onlyOwner {
        address[] memory treasuries = _subTreasuryList;
        for (uint256 i = 0; i < treasuries.length; i++) {
            if (treasuries[i] == treasury) {
                _subTreasuryList[i] = _subTreasuryList[treasuries.length - 1];
                _subTreasuryList.pop();
                break;
            }
        }
    }

    function updateClaimAmountByAddresses(address[] calldata _subTreasuries) external override onlyOperator returns (uint256) {
        return _updateClaimAmount(_subTreasuries);
    }

    function updateClaimAmount() external override onlyOperator returns (uint256) {
        address[] memory _subTreasuries = _subTreasuryList;
        return _updateClaimAmount(_subTreasuries);
    }

    function _updateClaimAmount(address[] memory _subTreasuries) internal returns (uint256) {
        uint256 beforeBalance = IKIP7(token).balanceOf(address(this));
        for (uint256 i = 0; i < _subTreasuries.length; i++) {
            IPoolManager(_subTreasuries[i]).claimAdminFee();
        }

        uint256 afterBalance = IKIP7(token).balanceOf(address(this));
        uint256 newAcc = accClaimedToken;
        if (afterBalance > beforeBalance) {
            newAcc = newAcc + afterBalance - beforeBalance;
            accClaimedToken = newAcc;
        }

        return newAcc;
    }

    function claimableAmount() public view override returns (uint256) {
        uint256 estimatedAmount;
        address[] memory _subTreasuries = _subTreasuryList;
        for (uint256 i = 0; i < _subTreasuries.length; i++) {
            estimatedAmount += IPoolManager(_subTreasuries[i]).claimableAdminFee();
        }

        return accClaimedToken + estimatedAmount;
    }

    function distribute(address to, uint256 amount) external {
        address airdropManager = addressBook.getAddress(bytes32("SEYE"));
        require(airdropManager == msg.sender, "KSDTreasury::airdrop: Invalid msg.sender");
        IKIP7(token).transfer(to, amount);
    }

    function subTreasuryList() external view returns (address[] memory) {
        return _subTreasuryList;
    }

    function subTreasury(uint256 i) external view returns (address) {
        return _subTreasuryList[i];
    }
}
