// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title PulseStrategy
 * @notice A Decentralized vPLS (Vouch-staked PLS) Reserve, allows xBond, iBond, an liquidity providers to claim PLStr, redeemable for vPLS.
 * @dev PLStr has a 0.5% burn on transfers (excluding claims/redemptions). LP receive 2x PLStr. claims expire after 90 days.
 */
contract PulseStrategy is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // --------------------------------------
    // Errors
    // --------------------------------------
    error InvalidAmount();
    error InsufficientBalance();
    error ZeroAddress();
    error InsufficientContractBalance();
    error NoEligibleTokens();
    error WeightUpdateTooSoon();
    error ZeroTokenSupply();
    error InsufficientAllowance();

    // --------------------------------------
    // Events
    // --------------------------------------
    event TokensDeposited(address indexed depositor, uint256 vPlsAmount);
    event PLStrClaimed(address indexed claimer, uint256 plstrAmount);
    event PLStrRedeemed(address indexed redeemer, uint256 plstrAmount, uint256 vPlsAmount);
    event WeightUpdated(uint256 newWeight);
    event PLStrBurned(address indexed from, uint256 amount);
    event RewardsUpdated(address indexed user, uint256 reward);
    event RewardsExpired(uint256 expiredAmount);

    // --------------------------------------
    // State Variables
    // --------------------------------------
    uint256 private totalPlstrMinted;
    uint256 private _iBondWeight;
    uint256 private _lastWeightUpdate;
    uint256 private _rewardPerTokenStored;
    mapping(address => uint256) private _userRewardPerTokenPaid;
    mapping(address => uint256) private _userRewards;
    uint256 private _totalClaimablePLStr;
    uint256 private _lastRewardTimestamp;

    // --------------------------------------
    // Immutable Variables
    // --------------------------------------
    address private immutable _vPls = 0x79BB3A0Ee435f957ce4f54eE8c3CFADc7278da0C;
    address private immutable _xBond = 0x2c858178F5D563Bb1B6C88e9ae58AF533cC8772e;
    address private immutable _iBond = 0xc087175be23F37DE50A94C36287feCC24a188993;
    address private immutable _inc = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d;
    address private immutable _plsx = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address private immutable _xBondPlsxLP = 0x1d21e8701d1b2b0C1c2dAd969be0c99515Ae004D;
    address private immutable _iBondIncLP = 0xd5e2D79527B2dcBF2eDAa85ADe3F10821d31A846;

    // --------------------------------------
    // Constants
    // --------------------------------------
    uint256 private constant _MIN_DEPOSIT = 100000e18;
    uint256 private constant _MIN_TRANSFER = 10e15;
    uint256 private constant _CLAIM_PRECISION = 1e18;
    uint256 private constant _WEIGHT_COOLDOWN = 86400;
    uint256 private constant _INITIAL_IBOND_WEIGHT = 2559614466000000000;
    uint256 private constant _BURN_FEE = 50;
    uint256 private constant _FEE_DENOMINATOR = 10000;
    uint256 private constant _LP_MULTIPLIER = 2;
    uint256 private constant _EXPIRATION_PERIOD = 90 days;
    uint256 private constant _SECONDS_PER_DAY = 86400;

    // --------------------------------------
    // Constructor
    // --------------------------------------
    constructor() ERC20("PulseStrategy", "PLStr") {
        _iBondWeight = _INITIAL_IBOND_WEIGHT;
        _lastWeightUpdate = block.timestamp;
    }

    // --------------------------------------
    // Internal Helpers
    // --------------------------------------
    function _getWeightedBalance(address account) private view returns (uint256) {
        IERC20 xBond = IERC20(_xBond);
        IERC20 iBond = IERC20(_iBond);
        IERC20 xBondPlsxLP = IERC20(_xBondPlsxLP);
        IERC20 iBondIncLP = IERC20(_iBondIncLP);
        uint256 iBondWeight = _iBondWeight;
        uint256 xBondBalance = xBond.balanceOf(account);
        uint256 iBondBalance = iBond.balanceOf(account);
        uint256 xBondPlsxLPBalance = xBondPlsxLP.balanceOf(account);
        uint256 iBondIncLPBalance = iBondIncLP.balanceOf(account);
        return xBondBalance +
               iBondBalance.mulDiv(iBondWeight, _CLAIM_PRECISION, Math.Rounding.Floor) +
               (xBondPlsxLPBalance * _LP_MULTIPLIER) +
               iBondIncLPBalance.mulDiv(iBondWeight * _LP_MULTIPLIER, _CLAIM_PRECISION, Math.Rounding.Floor);
    }

    function _getTotalEligibleSupply() private view returns (uint256) {
        IERC20 xBond = IERC20(_xBond);
        IERC20 iBond = IERC20(_iBond);
        IERC20 xBondPlsxLP = IERC20(_xBondPlsxLP);
        IERC20 iBondIncLP = IERC20(_iBondIncLP);
        uint256 iBondWeight = _iBondWeight;
        uint256 xBondTotalSupply = xBond.totalSupply();
        uint256 iBondTotalSupply = iBond.totalSupply();
        uint256 xBondPlsxLPTotalSupply = xBondPlsxLP.totalSupply();
        uint256 iBondIncLPTotalSupply = iBondIncLP.totalSupply();
        return xBondTotalSupply +
               iBondTotalSupply.mulDiv(iBondWeight, _CLAIM_PRECISION, Math.Rounding.Floor) +
               (xBondPlsxLPTotalSupply * _LP_MULTIPLIER) +
               iBondIncLPTotalSupply.mulDiv(iBondWeight * _LP_MULTIPLIER, _CLAIM_PRECISION, Math.Rounding.Floor);
    }

    function _updateReward(address account) private {
        _userRewards[account] = _earned(account);
        _userRewardPerTokenPaid[account] = _rewardPerTokenStored;
        emit RewardsUpdated(account, _userRewards[account]);
    }

    function _earned(address account) private view returns (uint256) {
        uint256 totalEligibleSupply = _getTotalEligibleSupply();
        if (totalEligibleSupply == 0) return 0;
        uint256 weightedBalance = _getWeightedBalance(account);
        uint256 rewardDelta = _rewardPerTokenStored - _userRewardPerTokenPaid[account];
        if (rewardDelta == 0) return _userRewards[account];
        return _userRewards[account] + weightedBalance.mulDiv(rewardDelta, _CLAIM_PRECISION, Math.Rounding.Ceil);
    }

    function _cleanExpiredRewards() private returns (uint256) {
        uint256 totalClaimable = _totalClaimablePLStr;
        if (totalClaimable == 0 || _lastRewardTimestamp == 0) {
            return 0;
        }

        uint256 expiredAmount = 0;
        if (block.timestamp >= _lastRewardTimestamp + _EXPIRATION_PERIOD) {
            expiredAmount = totalClaimable;
            _totalClaimablePLStr = 0;
            _lastRewardTimestamp = 0;
            _rewardPerTokenStored = 0;
            emit RewardsExpired(expiredAmount);
        }

        return expiredAmount;
    }

    // --------------------------------------
    // Weight Update Functionality
    // --------------------------------------
    function updateWeight() external {
        if (msg.sender == address(0)) revert ZeroAddress();
        if (block.timestamp < _lastWeightUpdate + _WEIGHT_COOLDOWN) revert WeightUpdateTooSoon();

        uint256 incSupply = IERC20(_inc).totalSupply();
        uint256 plsxSupply = IERC20(_plsx).totalSupply();
        if (incSupply == 0 || plsxSupply == 0) revert ZeroTokenSupply();

        uint256 newWeight = plsxSupply.mulDiv(_CLAIM_PRECISION, incSupply, Math.Rounding.Floor);
        if (newWeight == 0) revert InvalidAmount();

        _iBondWeight = newWeight;
        _lastWeightUpdate = block.timestamp;

        emit WeightUpdated(newWeight);
    }

    // --------------------------------------
    // Deposit Functionality
    // --------------------------------------
    function depositTokens(uint256 vPlsAmount) external nonReentrant {
        if (msg.sender == address(0)) revert ZeroAddress();
        if (vPlsAmount < _MIN_DEPOSIT) revert InvalidAmount();
        IERC20 vPls = IERC20(_vPls);
        address thisContract = address(this);
        if (vPls.allowance(msg.sender, thisContract) < vPlsAmount)
            revert InsufficientAllowance();
        if (vPls.balanceOf(msg.sender) < vPlsAmount)
            revert InsufficientBalance();

        _cleanExpiredRewards();

        uint256 plstrToDistribute;
        uint256 contractTotalSupply = totalSupply();
        uint256 totalClaimable = _totalClaimablePLStr;
        uint256 vPlsBalance = vPls.balanceOf(thisContract);
        uint256 effectiveSupply = contractTotalSupply + totalClaimable;

        if (effectiveSupply == 0) {
            plstrToDistribute = vPlsAmount;
        } else {
            plstrToDistribute = vPlsAmount.mulDiv(effectiveSupply, vPlsBalance, Math.Rounding.Ceil);
            if (plstrToDistribute == 0) revert InvalidAmount();
        }

        uint256 totalEligibleSupply = _getTotalEligibleSupply();
        if (totalEligibleSupply > 0) {
            _rewardPerTokenStored += plstrToDistribute.mulDiv(_CLAIM_PRECISION, totalEligibleSupply, Math.Rounding.Floor);
            _totalClaimablePLStr = totalClaimable + plstrToDistribute;
            _lastRewardTimestamp = block.timestamp;
        }

        vPls.safeTransferFrom(msg.sender, thisContract, vPlsAmount);

        emit TokensDeposited(msg.sender, vPlsAmount);
    }

    // --------------------------------------
    // Claim Functionality
    // --------------------------------------
    function claimPLStr() external nonReentrant {
        if (msg.sender == address(0)) revert ZeroAddress();
        _cleanExpiredRewards();

        _updateReward(msg.sender);
        uint256 reward = _userRewards[msg.sender];
        if (reward == 0) revert NoEligibleTokens();
        if (reward > _totalClaimablePLStr) revert InsufficientContractBalance();

        _userRewards[msg.sender] = 0;
        _totalClaimablePLStr -= reward;
        _mint(msg.sender, reward);
        totalPlstrMinted += reward;

        emit PLStrClaimed(msg.sender, reward);
    }

    // --------------------------------------
    // Redemption Functionality
    // --------------------------------------
    function redeemPLStr(uint256 plstrAmount) external nonReentrant {
        if (msg.sender == address(0)) revert ZeroAddress();
        if (plstrAmount == 0 || balanceOf(msg.sender) < plstrAmount) revert InvalidAmount();

        _cleanExpiredRewards();

        uint256 contractTotalSupply = totalSupply();
        uint256 totalClaimable = _totalClaimablePLStr;
        uint256 effectiveSupply = contractTotalSupply + totalClaimable;
        if (effectiveSupply == 0) revert InsufficientContractBalance();

        IERC20 vPls = IERC20(_vPls);
        address thisContract = address(this);
        uint256 vPlsBalance = vPls.balanceOf(thisContract);
        if (vPlsBalance == 0) revert InsufficientContractBalance();

        uint256 vPlsAmount = vPlsBalance.mulDiv(plstrAmount, effectiveSupply, Math.Rounding.Ceil);
        if (vPlsAmount == 0) revert InvalidAmount();

        _burn(msg.sender, plstrAmount);
        vPls.safeTransfer(msg.sender, vPlsAmount);

        emit PLStrRedeemed(msg.sender, plstrAmount, vPlsAmount);
    }

    // --------------------------------------
    // Transfer Functionality with Burn
    // --------------------------------------
    function _update(address from, address to, uint256 amount) internal override {
        if (amount < _MIN_TRANSFER) revert InvalidAmount();
        if (from == address(0) || to == address(0)) {
            super._update(from, to, amount);
            return;
        }

        uint256 burnAmount = amount.mulDiv(_BURN_FEE, _FEE_DENOMINATOR, Math.Rounding.Floor);
        uint256 transferAmount;
        unchecked { transferAmount = amount - burnAmount; }

        if (burnAmount > 0) {
            super._update(from, address(0), burnAmount);
            emit PLStrBurned(from, burnAmount);
        }

        super._update(from, to, transferAmount);
    }

    // --------------------------------------
    // View Functions
    // --------------------------------------
    function getBasicMetrics() external view returns (
        uint256 contractTotalSupply,
        uint256 vPlsBalance,
        uint256 plstrMinted,
        uint256 totalBurned,
        uint256 backingRatio,
        uint256 totalClaimablePLStr
    ) {
        address thisContract = address(this);
        contractTotalSupply = totalSupply();
        vPlsBalance = IERC20(_vPls).balanceOf(thisContract);
        plstrMinted = totalPlstrMinted;
        totalBurned = totalPlstrMinted - contractTotalSupply;
        backingRatio = contractTotalSupply == 0 ? _CLAIM_PRECISION :
            vPlsBalance.mulDiv(_CLAIM_PRECISION, contractTotalSupply + totalClaimablePLStr, Math.Rounding.Floor);
        totalClaimablePLStr = _totalClaimablePLStr;
    }

    function getRewardMetrics() external view returns (
        uint256 rewardPerToken,
        uint256 totalPlstrPerBond
    ) {
        rewardPerToken = _rewardPerTokenStored;
        uint256 totalEligibleSupply = _getTotalEligibleSupply();
        totalPlstrPerBond = totalEligibleSupply == 0 ? 0 :
            _rewardPerTokenStored.mulDiv(totalEligibleSupply, _CLAIM_PRECISION, Math.Rounding.Floor);
    }

    function getClaimEligibility(address user) external view returns (
        uint256 claimablePLStr,
        uint256 xBondBalance,
        uint256 iBondBalance,
        uint256 xBondPlsxLPBalance,
        uint256 iBondIncLPBalance
    ) {
        xBondBalance = IERC20(_xBond).balanceOf(user);
        iBondBalance = IERC20(_iBond).balanceOf(user);
        xBondPlsxLPBalance = IERC20(_xBondPlsxLP).balanceOf(user);
        iBondIncLPBalance = IERC20(_iBondIncLP).balanceOf(user);
        claimablePLStr = _earned(user);
    }

    function getCurrentWeight() external view returns (uint256) {
        return _iBondWeight;
    }

    function getLastWeightUpdate() external view returns (uint256) {
        return _lastWeightUpdate;
    }

    function getDaysUntilExpiration() external view returns (uint256) {
        if (_lastRewardTimestamp == 0 || block.timestamp >= _lastRewardTimestamp + _EXPIRATION_PERIOD) {
            return 0;
        }
        uint256 secondsRemaining = (_lastRewardTimestamp + _EXPIRATION_PERIOD) - block.timestamp;
        return secondsRemaining / _SECONDS_PER_DAY;
    }
}