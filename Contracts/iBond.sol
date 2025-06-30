// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PulseStrategy
 * @notice A Decentralized INC (Incentive token) Reserve, allowing for the issuance and redemption of iBond for a proportional amount of INC in the reserves.
 * @dev iBond has a 0.5% tax on transfers (0.25% burned, 0.25% to a origin Address, excluding redemptions).
 */
contract PulseStrategy is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // --------------------------------------
    // Errors
    // --------------------------------------
    error InvalidAmount();
    error InsufficientBalance();
    error ZeroAddress();
    error IssuancePeriodEnded();
    error InsufficientContractBalance();
    error InsufficientAllowance();

    // --------------------------------------
    // Events
    // --------------------------------------
    event SharesIssued(address indexed buyer, uint256 shares, uint256 totalFee);
    event SharesRedeemed(address indexed redeemer, uint256 shares, uint256 inc);
    event TransferTaxApplied(address indexed from, address indexed to, uint256 amountAfterTax, uint256 iBondToOriginAddress, uint256 burned);

    // --------------------------------------
    // State Variables
    // --------------------------------------
    uint256 private _totalSupplyMinted;
    uint48 private _deploymentTime;

    // --------------------------------------
    // Immutable Variables
    // --------------------------------------
    address private immutable _inc = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d;
    address private immutable _originAddress;

    // --------------------------------------
    // Constants
    // --------------------------------------
    uint16 private constant _FEE_BASIS_POINTS = 50; // 0.5%
    uint256 private constant _MIN_LIQUIDITY = 1e18; // 1 INC
    uint256 private constant _MIN_TRANSFER = 10e15; // 0.01 iBond
    uint16 private constant _BASIS_DENOMINATOR = 10000; // 10,000
    uint256 private constant _ISSUANCE_PERIOD = 180 days; // ~6 months

    // --------------------------------------
    // Constructor
    // --------------------------------------
    constructor() ERC20("PulseStrategy", "iBond") {
        _originAddress = msg.sender;
        _deploymentTime = uint48(block.timestamp);
    }

    // --------------------------------------
    // Internal Helpers
    // --------------------------------------
    function _calculateFee(uint256 amount) private pure returns (uint256) {
        return (amount * _FEE_BASIS_POINTS) / _BASIS_DENOMINATOR;
    }

    // --------------------------------------
    // Transfer and Tax Logic
    // --------------------------------------
    function _update(address from, address to, uint256 value) internal override {
        if (value < _MIN_TRANSFER && from != address(0) && to != address(0)) revert InvalidAmount();
        if (from != address(0) && balanceOf(from) < value) revert InsufficientBalance();

        if (from == _originAddress || to == _originAddress){
            super._update(from, to, value);
            emit TransferTaxApplied(from, to, value, 0, 0);
            return;
        }

        uint256 fee = _calculateFee(value);
        uint256 burnShare = (fee * 50) / 100;
        uint256 originAddressShare = fee - burnShare;
        uint256 amountAfterTax = value - fee;

        if (burnShare > 0) _burn(from, burnShare);
        if (originAddressShare > 0) super._update(from, _originAddress, originAddressShare);
        super._update(from, to, amountAfterTax);

        emit TransferTaxApplied(from, to, amountAfterTax, originAddressShare, burnShare);
    }

    // --------------------------------------
    // Share Issuance and Redemption
    // --------------------------------------
    function issueShares(uint256 incAmount) external nonReentrant {
        if (incAmount < _MIN_LIQUIDITY || block.timestamp > _deploymentTime + _ISSUANCE_PERIOD)
            revert IssuancePeriodEnded();
        if (IERC20(_inc).allowance(msg.sender, address(this)) < incAmount) revert InsufficientAllowance();

        IERC20(_inc).safeTransferFrom(msg.sender, address(this), incAmount);
        uint256 fee = _calculateFee(incAmount);

        uint256 shares = incAmount - fee;
        uint256 feeToOriginAddress = fee / 2;
        uint256 sharesToOriginAddress = feeToOriginAddress;

        if (feeToOriginAddress > 0) IERC20(_inc).safeTransfer(_originAddress, feeToOriginAddress);
        _mint(msg.sender, shares);
        if (sharesToOriginAddress > 0) _mint(_originAddress, sharesToOriginAddress);
        _totalSupplyMinted += shares + sharesToOriginAddress;
        emit SharesIssued(msg.sender, shares, fee);
    }

    function redeemShares(uint256 shareAmount) external nonReentrant {
        if (shareAmount == 0 || balanceOf(msg.sender) < shareAmount) revert InvalidAmount();
        uint256 incAmount = (IERC20(_inc).balanceOf(address(this)) * shareAmount) / totalSupply();
        if (incAmount == 0) revert InsufficientContractBalance();

        _burn(msg.sender, shareAmount);
        IERC20(_inc).safeTransfer(msg.sender, incAmount);
        emit SharesRedeemed(msg.sender, shareAmount, incAmount);
    }

    // --------------------------------------
    // View Functions
    // --------------------------------------
    function getContractMetrics() external view returns (
        uint256 contractTotalSupply,
        uint256 incBalance,
        uint256 totalMinted,
        uint256 totalBurned,
        uint256 incBackingRatio
    ) {
        uint256 supply = totalSupply();
        contractTotalSupply = supply;
        incBalance = IERC20(_inc).balanceOf(address(this));
        totalMinted = _totalSupplyMinted;
        totalBurned = totalMinted - supply;
        incBackingRatio = supply == 0 ? 0 : (incBalance * 1e18) / supply;
    }

    function getIssuanceStatus() external view returns (bool isActive, uint256 timeRemaining) {
        isActive = block.timestamp <= _deploymentTime + _ISSUANCE_PERIOD;
        timeRemaining = isActive ? _deploymentTime + _ISSUANCE_PERIOD - block.timestamp : 0;
    }
}