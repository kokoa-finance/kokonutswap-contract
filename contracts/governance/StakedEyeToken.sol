// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/WadRayMath.sol";
import "../library/openzeppelin/contracts/utils/Math.sol";
import "../library/openzeppelin/contracts/utils/SafeCast.sol";
import "../interface/IBeneficiary.sol";
import "../interface/IStakedToken.sol";
import "../interface/IDistributionTreasury.sol";
import "../library/kip/KIP7Detailed.sol";
import "../library/AccessControl.sol";
import "../library/Pausable.sol";

contract StakedEyeToken is KIP7Detailed, Pausable, IStakedToken {
    using WadRayMath for uint256;

    uint256 public constant PRECISION = 1e12;

    IKIP7 public EYE;
    IBeneficiary public beneficiary;
    uint256 internal _liquidityIndex;

    // for tracking amount of staking/unstaking/pending
    mapping(address => uint256) public override unstakeCount;
    mapping(address => uint256) public override claimCount;
    mapping(address => mapping(uint256 => UnstakeRecord)) internal _unstakeRecord;

    uint256 public override lockUpPeriod;
    uint256 public underlyingBalance;

    address[] private _registeredAirdropTokenList;
    mapping(address => AirdropInfo) public airdropInfo;
    mapping(address => mapping(address => int256)) public rewardDebt; // token => usr => debt
    uint256 public constant ACC_REWARD_PRECISION = 1e18;
    uint256 public instantUnstakeFee; // 10000 == 100%

    function __StakedEyeToken_init(
        string memory _name,
        string memory _symbol,
        address _EYE,
        uint256 _lockUpPeriod
    ) public initializer {
        require(_EYE != address(0), "StakedEyeToken::init: zero address");
        __Pausable_init();
        __KIP7Detailed_init(_name, _symbol, 18);
        EYE = IKIP7(_EYE);
        _liquidityIndex = WadRayMath.ray();
        lockUpPeriod = _lockUpPeriod;
    }

    function config(bytes32 what, uint256 data) external onlyOwner {
        if (what == "lockUpPeriod") lockUpPeriod = data;
        else if (what == "instantUnstakeFee") {
            require(data < 10000, "StakedEyeToken::config: invalid param");
            instantUnstakeFee = data;
        } else revert("unrecognized");
    }

    function config(bytes32 what, address value) external onlyOwner {
        if (what == "beneficiary") {
            require(value != address(0), "StakedEyeToken::config: 0 address");
            beneficiary = IBeneficiary(value);
        } else {
            revert("unrecognized");
        }
    }

    function stake(address to, uint256 amount) external override {
        _release();
        updateAirdrops();

        uint256 amountScaled = _toRawAmount(amount);
        require(amountScaled != 0, "StakedEyeToken::stake: too small amount");
        _balances[to] = _balances[to] + amountScaled;
        _totalSupply = _totalSupply + amountScaled;
        emit Transfer(address(0), to, amount);

        EYE.transferFrom(msg.sender, address(this), amount);
        underlyingBalance += amount;
        emit Stake(msg.sender, to, amount, _liquidityIndex);

        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 accRewardPerShare = airdropInfo[token].accRewardPerShare;
            rewardDebt[token][to] += SafeCast.toInt256((amountScaled * accRewardPerShare) / ACC_REWARD_PRECISION);
        }
    }

    function unstake(address to, uint256 amount) external override {
        _release();
        updateAirdrops();

        uint256 amountScaled = _toRawAmount(amount);
        require(amountScaled != 0, "StakedEyeToken::unstake: too small amount");
        _balances[msg.sender] = _balances[msg.sender] - amountScaled;
        _totalSupply = _totalSupply - amountScaled;
        emit Transfer(msg.sender, address(0), amount);

        uint256 count = unstakeCount[to];
        if (count > 0 && _unstakeRecord[to][count - 1].timestamp == block.timestamp) {
            _unstakeRecord[to][count - 1].amount += amount;
        } else {
            _unstakeRecord[to][count] = UnstakeRecord({timestamp: block.timestamp, amount: amount});
            unstakeCount[to] += 1;
        }
        emit Unstake(msg.sender, to, amount, _liquidityIndex);

        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 accRewardPerShare = airdropInfo[token].accRewardPerShare;
            rewardDebt[token][to] -= SafeCast.toInt256((amountScaled * accRewardPerShare) / ACC_REWARD_PRECISION);
        }
    }

    function instantUnstake(address to, uint256 amount) external override {
        _release();
        updateAirdrops();

        uint256 amountScaled = _toRawAmount(amount);
        require(amountScaled != 0, "StakedEyeToken::unstake: too small amount");
        _balances[msg.sender] = _balances[msg.sender] - amountScaled;
        _totalSupply = _totalSupply - amountScaled;
        emit Transfer(msg.sender, address(0), amount);

        address burner = 0x000000000000000000000000000000000DEad141;
        uint256 feeAmount = (amount * instantUnstakeFee) / 10000;
        require(instantUnstakeFee > 0, "StakedEyeToken::instantUnstake: invalid instantUnstakeFee");
        EYE.transfer(burner, feeAmount);
        EYE.transfer(to, amount - feeAmount);
        underlyingBalance -= amount;
        emit InstantUnstake(msg.sender, to, amount, _liquidityIndex);

        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 accRewardPerShare = airdropInfo[token].accRewardPerShare;
            rewardDebt[token][to] -= SafeCast.toInt256((amountScaled * accRewardPerShare) / ACC_REWARD_PRECISION);
        }
    }

    function pending(address account) external view returns (uint256 completed, uint256 yet) {
        completed = 0;
        yet = 0;
        uint256 safeCount = Math.min(claimCount[account] + 100, unstakeCount[account]);
        for (uint256 i = claimCount[account]; i < safeCount; i++) {
            if (block.timestamp - _unstakeRecord[account][i].timestamp >= lockUpPeriod) {
                completed = completed + _unstakeRecord[account][i].amount;
            } else {
                yet = yet + _unstakeRecord[account][i].amount;
            }
        }
    }

    function claim(address account) external override {
        require(unstakeCount[account] > 0, "StakedEyeToken::claim: should unstake first");
        _release();
        uint256 claimAmount = 0;

        uint256 safeCount = Math.min(claimCount[account] + 100, unstakeCount[account]);
        for (uint256 i = claimCount[account]; i < safeCount; i++) {
            if (block.timestamp - _unstakeRecord[account][i].timestamp >= lockUpPeriod) {
                claimAmount = claimAmount + _unstakeRecord[account][i].amount;
                claimCount[account] += 1;
            } else {
                break;
            }
        }
        underlyingBalance -= claimAmount;
        EYE.transfer(account, claimAmount);
        emit Claim(account, claimAmount);
    }

    function unstakeRecord(address user, uint256 index) external view override returns (UnstakeRecord memory) {
        return _unstakeRecord[user][index];
    }

    function registeredAirdropTokenList() external view returns (address[] memory) {
        return _registeredAirdropTokenList;
    }

    function liquidityIndex() public view override returns (uint256) {
        uint256 unreflectedAmount = EYE.balanceOf(address(this)) + beneficiary.claimableToken(address(this)) - underlyingBalance;
        if (unreflectedAmount == 0 || _totalSupply == 0) {
            return _liquidityIndex;
        }
        return _liquidityIndex + _calcEarningPerShare(unreflectedAmount);
    }

    function _fromRawAmount(uint256 rawAmount) internal view returns (uint256) {
        return rawAmount.rayMul(_liquidityIndex) / PRECISION;
    }

    function _toRawAmount(uint256 amount) internal view returns (uint256) {
        return (amount * PRECISION).rayDiv(_liquidityIndex);
    }

    function rawBalanceOf(address usr) external view override returns (uint256) {
        return _balances[usr];
    }

    function rawTotalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address usr) public view virtual override(IKIP7, KIP7) returns (uint256) {
        return _balances[usr].rayMul(liquidityIndex()) / PRECISION;
    }

    function totalSupply() public view virtual override(IKIP7, KIP7) returns (uint256) {
        return _totalSupply.rayMul(liquidityIndex()) / PRECISION;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        require(sender != address(0), "StakedEyeToken::_transfer: transfer from the zero address");
        require(recipient != address(0), "StakedEyeToken::_transfer: transfer to the zero address");

        _release();
        uint256 amountScaled = _toRawAmount(amount);

        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            claimAirdropToken(token, sender);
            uint256 accRewardPerShare = airdropInfo[token].accRewardPerShare;
            rewardDebt[token][sender] -= SafeCast.toInt256((amountScaled * accRewardPerShare) / ACC_REWARD_PRECISION);
            rewardDebt[token][recipient] += SafeCast.toInt256((amountScaled * accRewardPerShare) / ACC_REWARD_PRECISION);
        }

        _balances[sender] = _balances[sender] - amountScaled;
        _balances[recipient] = _balances[recipient] + amountScaled;
        emit Transfer(sender, recipient, amount);
    }

    function _release() internal {
        beneficiary.claimToken(address(this));
        _updateBalance();
    }

    function _calcEarningPerShare(uint256 amount) internal view returns (uint256) {
        return (WadRayMath.ray() * amount * PRECISION) / _totalSupply;
    }

    function _updateBalance() internal {
        uint256 accumulatedAmount = EYE.balanceOf(address(this)) - underlyingBalance;
        if (accumulatedAmount > 0 && _totalSupply > 0) {
            _liquidityIndex += _calcEarningPerShare(accumulatedAmount);
            underlyingBalance += accumulatedAmount;
            emit Earn(block.timestamp, accumulatedAmount, _liquidityIndex);
        }
    }

    function earn(uint256 amount) external override {
        _release();
        if (amount > 0) {
            EYE.transferFrom(msg.sender, address(this), amount);
            _updateBalance();
        }
    }

    function addAirdrop(address token, address treasury) external onlyOwner {
        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            require(tokenList[i] != token, "StakedEyeToken::addAirdrop: already registered");
        }
        require(airdropInfo[token].accRewardPerShare == 0, "StakedEyeToken::addAirdrop: once upon a time..");

        _registeredAirdropTokenList.push(token);
        airdropInfo[token] = AirdropInfo({treasury: treasury, accRewardPerShare: 0, lastVestedAmount: 0});
    }

    function removeAirdrop(address token) external onlyOwner {
        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            if (tokenList[i] == token) {
                _registeredAirdropTokenList[i] = _registeredAirdropTokenList[tokenList.length - 1];
                _registeredAirdropTokenList.pop();
                break;
            }
        }
    }

    function updateAirdrop(address token) public {
        if (_totalSupply > 0) {
            AirdropInfo memory info = airdropInfo[token];
            IDistributionTreasury treasury = IDistributionTreasury(info.treasury);
            uint256 vestedAmount = treasury.accClaimedToken();
            uint256 reward = vestedAmount - info.lastVestedAmount;
            info.lastVestedAmount = vestedAmount;
            info.accRewardPerShare = info.accRewardPerShare + ((reward * ACC_REWARD_PRECISION) / _totalSupply);
            airdropInfo[token] = info;
            emit UpdateAirdrop(token, _totalSupply, info.accRewardPerShare, info.lastVestedAmount);
        }
    }

    function updateAirdrops() public {
        address[] memory tokenList = _registeredAirdropTokenList;
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            updateAirdrop(token);
        }
    }

    function claimableAirdropToken(address token, address usr) external view returns (uint256) {
        AirdropInfo memory info = airdropInfo[token];
        uint256 _accRewardPerShare = info.accRewardPerShare;
        if (_totalSupply > 0) {
            IDistributionTreasury treasury = IDistributionTreasury(info.treasury);
            uint256 vestedAmount = treasury.accClaimedToken();
            uint256 reward = vestedAmount - info.lastVestedAmount;
            _accRewardPerShare = info.accRewardPerShare + ((reward * ACC_REWARD_PRECISION) / _totalSupply);
        }
        int256 claimable = SafeCast.toInt256((_balances[usr] * _accRewardPerShare) / ACC_REWARD_PRECISION) - rewardDebt[token][usr];
        claimable = claimable > int256(0) ? claimable : int256(0);
        return SafeCast.toUint256(claimable);
    }

    function claimAirdropToken(address token, address usr) public whenNotPaused {
        updateAirdrop(token);

        AirdropInfo memory info = airdropInfo[token];
        int256 accumulatedReward = SafeCast.toInt256((_balances[usr] * info.accRewardPerShare) / ACC_REWARD_PRECISION);
        int256 claimable = accumulatedReward - rewardDebt[token][usr];
        claimable = claimable > int256(0) ? claimable : int256(0);
        if (claimable == int256(0)) {
            return;
        }

        uint256 amount = SafeCast.toUint256(claimable);
        rewardDebt[token][usr] = accumulatedReward;
        IDistributionTreasury(info.treasury).distribute(usr, amount);
        emit ClaimAirdropToken(token, usr, amount);
    }
}
