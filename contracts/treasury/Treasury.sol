// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/openzeppelin/contracts/utils/Math.sol";
import "../interface/ITreasury.sol";
import "../interface/IAddressBook.sol";
import "../library/kip/IKIP7.sol";
import "../library/Pausable.sol";
import "../interface/IBeneficiary.sol";

contract Treasury is Pausable, ITreasury {
    IAddressBook public addressBook;
    mapping(address => BondRecord[]) public bondRecord;
    mapping(address => uint256) public claimCount;
    uint256 public totalCreatedBondAmount;
    uint256 public totalClaimedBondAmount;

    function __Treasury_init(address addressBook_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
    }

    function getBondRecord(address usr, uint256 index) external view override returns (BondRecord memory) {
        return bondRecord[usr][index];
    }

    function getBondRecordLength(address usr) external view override returns (uint256) {
        return bondRecord[usr].length;
    }

    function creatableBondAmount() external view override returns (uint256) {
        IKIP7 EYE = IKIP7(addressBook.getAddress(bytes32("EYE")));
        IBeneficiary beneficiary = IBeneficiary(addressBook.getAddress(bytes32("rewardBeneficiary")));
        uint256 pendingAmount = totalCreatedBondAmount - totalClaimedBondAmount;
        uint256 balance = EYE.balanceOf(address(this));
        uint256 claimable = beneficiary.claimableToken(address(this));
        return balance + claimable - pendingAmount;
    }

    function createBond(
        address usr,
        uint256 amount,
        uint256 vestingPeriod
    ) external override onlyAdmin whenNotPaused {
        IBeneficiary beneficiary = IBeneficiary(addressBook.getAddress(bytes32("rewardBeneficiary")));
        beneficiary.claimToken(address(this));

        IKIP7 EYE = IKIP7(addressBook.getAddress(bytes32("EYE")));
        uint256 pendingAmount = totalCreatedBondAmount - totalClaimedBondAmount;
        require(EYE.balanceOf(address(this)) >= amount + pendingAmount, "Treasury::createBond: insufficient amount");

        totalCreatedBondAmount += amount;
        bondRecord[usr].push(BondRecord({amount: amount, claimedAmount: 0, createdAt: block.timestamp, vestingPeriod: vestingPeriod}));
        emit BondCreated(usr, amount, block.timestamp, vestingPeriod, bondRecord[usr].length - 1);
    }

    function pendingBond(address usr) public view override returns (uint256 completed, uint256 yet) {
        uint256 usrClaimCount = claimCount[usr];
        uint256 bondRecordLength = bondRecord[usr].length;

        if (bondRecordLength <= 0) {
            return (0, 0);
        }

        completed = 0;
        yet = 0;
        uint256 start = usrClaimCount;
        uint256 end = Math.min(start + 100, bondRecordLength);

        BondRecord[] memory records = bondRecord[usr];
        for (uint256 i = start; i < end; i++) {
            BondRecord memory record = records[i];
            uint256 vestedAmount = Math.min((record.amount * (block.timestamp - record.createdAt)) / (record.vestingPeriod), record.amount);
            uint256 claimableAmount = vestedAmount - record.claimedAmount;
            completed += claimableAmount;
            yet += record.amount - record.claimedAmount - claimableAmount;
        }
    }

    function claimBond(address usr) public override {
        uint256 usrClaimCount = claimCount[usr];
        uint256 bondRecordLength = bondRecord[usr].length;
        IKIP7 EYE = IKIP7(addressBook.getAddress(bytes32("EYE")));

        uint256 start = usrClaimCount;
        uint256 end = Math.min(start + 100, bondRecordLength);
        BondRecord[] memory records = bondRecord[usr];
        for (uint256 i = start; i < end; i++) {
            BondRecord memory record = records[i];
            uint256 vestedAmount = Math.min((record.amount * (block.timestamp - record.createdAt)) / (record.vestingPeriod), record.amount);
            uint256 claimableAmount = vestedAmount - record.claimedAmount;

            EYE.transfer(usr, claimableAmount);
            totalClaimedBondAmount += claimableAmount;
            bondRecord[usr][i].claimedAmount = record.claimedAmount + claimableAmount;
            if (record.amount <= record.claimedAmount + claimableAmount) {
                claimCount[usr] += 1;
            }
            emit BondClaimed(usr, claimableAmount, block.timestamp, i);
        }
    }
}
