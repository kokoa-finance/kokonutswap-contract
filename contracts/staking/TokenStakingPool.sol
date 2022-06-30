// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../interface/IStakingPool.sol";
import "../interface/IAddressBook.sol";
import "../library/AccessControl.sol";
import "../library/Pausable.sol";
import "../library/WadRayMath.sol";
import "../library/kip/IKIP7.sol";
import "../library/openzeppelin/contracts/utils/SafeCast.sol";
import "../interface/IBeneficiary.sol";
import "../interface/IStakedToken.sol";

abstract contract TokenStakingPool is Pausable, IStakingPool {
    using WadRayMath for uint256;

    IAddressBook public immutable ADDRESS_BOOK;

    IKIP7 internal _token;

    uint256 public accRewardPerShare;
    uint256 public lastAccClaimedAmountFromVesting;
    mapping(address => int256) public rewardDebt;

    uint256 public override totalSupply;
    mapping(address => uint256) public override balanceOf;

    bytes32[50] private __storageBuffer;

    constructor(address ADDRESS_BOOK_) {
        ADDRESS_BOOK = IAddressBook(ADDRESS_BOOK_);
    }

    function __TokenStakingPool_init(address token_) public initializer {
        __TokenStakingPool_init_unchained(token_, msg.sender);
    }

    function __TokenStakingPool_init(address token_, address owner_) public initializer {
        __TokenStakingPool_init_unchained(token_, owner_);
    }

    function __TokenStakingPool_init_unchained(address token_, address owner_) private {
        __Pausable_init(owner_);
        _token = IKIP7(token_);
    }

    function config(bytes32 key, address value) external onlyOwner {
        if (key == "token") {
            _token = IKIP7(value);
        } else {
            revert("unrecognized param");
        }
    }

    function beneficiary() public view virtual returns (IBeneficiary);

    function stake(address to, uint256 amount) public virtual override whenNotPaused {
        release();
        rewardDebt[to] += SafeCast.toInt256(amount.wadMul(accRewardPerShare));

        _token.transferFrom(msg.sender, address(this), amount);
        balanceOf[to] = balanceOf[to] + amount;
        totalSupply = totalSupply + amount;

        emit Stake(msg.sender, to, amount);
    }

    function unstake(address to, uint256 amount) external override whenNotPaused {
        release();
        rewardDebt[msg.sender] -= SafeCast.toInt256(amount.wadMul(accRewardPerShare));

        _token.transfer(to, amount);
        balanceOf[msg.sender] = balanceOf[msg.sender] - amount;
        totalSupply = totalSupply - amount;

        emit Unstake(msg.sender, to, amount);
    }

    function release() public whenNotPaused {
        if (totalSupply > 0) {
            IBeneficiary _beneficiary = beneficiary();
            _beneficiary.claimToken(address(this));
            (, uint256 accClaimedToken, , ) = _beneficiary.accountInfo(address(this));
            uint256 reward = accClaimedToken - lastAccClaimedAmountFromVesting;
            lastAccClaimedAmountFromVesting = accClaimedToken;
            accRewardPerShare = accRewardPerShare + ((reward * WadRayMath.WAD) / totalSupply);
            emit Release(totalSupply, accRewardPerShare, lastAccClaimedAmountFromVesting);
        }
    }

    function claimableReward(address usr) external view override returns (uint256 claimable) {
        uint256 _accRewardPerShare = accRewardPerShare;
        if (totalSupply > 0) {
            IBeneficiary _beneficiary = beneficiary();
            uint256 claimableToken = _beneficiary.claimableToken(address(this));
            (, uint256 accClaimedToken, , ) = _beneficiary.accountInfo(address(this));
            uint256 reward = accClaimedToken + claimableToken - lastAccClaimedAmountFromVesting;
            _accRewardPerShare = _accRewardPerShare + ((reward * WadRayMath.WAD) / totalSupply);
        }
        claimable = SafeCast.toUint256(SafeCast.toInt256(balanceOf[usr].wadMul(_accRewardPerShare)) - rewardDebt[usr]);
    }

    function _claimReward(address usr) internal returns (uint256 amount) {
        release();

        int256 accumulatedReward = SafeCast.toInt256(balanceOf[usr].wadMul(accRewardPerShare));
        amount = SafeCast.toUint256(accumulatedReward - rewardDebt[usr]);

        rewardDebt[usr] = accumulatedReward;
    }

    // @deprecated
    function claimReward(address usr) external override whenNotPaused {
        uint256 amount = _claimReward(usr);
        if (amount == 0) {
            return;
        }

        IKIP7 rewardToken = _getKokos();
        IStakedToken stakedRewardToken = IStakedToken(ADDRESS_BOOK.getAddress(bytes32("SEYE")));

        rewardToken.approve(address(stakedRewardToken), amount);
        stakedRewardToken.stake(usr, amount);
        emit ClaimReward(usr, amount);
    }

    function claimUnstakedReward(address usr) external override whenNotPaused {
        uint256 amount = _claimReward(usr);
        if (amount == 0) {
            return;
        }

        IKIP7 rewardToken = _getKokos();

        rewardToken.transfer(usr, amount);
        emit ClaimReward(usr, amount);
    }

    function token() external view override returns (address) {
        return address(_token);
    }

    function _getKokos() internal view returns (IKIP7) {
        return IKIP7(ADDRESS_BOOK.getAddress(bytes32("EYE")));
    }
}
