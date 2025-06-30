// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title PulseStrategy
 * @notice A Decentralized PLSX (PulseX) Reserve, allowing for the issuance/redemption of xBond for proportional amount of PLSX in reserves.
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
    event SharesRedeemed(address indexed redeemer, uint256 shares, uint256 plsx);
    event TransferTaxApplied(address indexed from, address indexed to, uint256 amountAfterTax, uint256 xBondToOriginAddress, uint256 burned);

    // --------------------------------------
    // State Variables
    // --------------------------------------
    uint256 private _totalSupplyMinted;
    uint48 private _deploymentTime;

    // --------------------------------------
    // Immutable Variables
    // --------------------------------------
    address private immutable _plsx = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address private immutable _originAddress;

    // --------------------------------------
    // Constants
    // --------------------------------------
    uint16 private constant _FEE_BASIS_POINTS = 50; // 0.5%
    uint256 private constant _MIN_LIQUIDITY = 1e18; // 1 PLSX
    uint256 private constant _MIN_TRANSFER = 10e15; // 0.01 xBond
    uint16 private constant _BASIS_DENOMINATOR = 10000; // 10,000
    uint256 private constant _ISSUANCE_PERIOD = 180 days; // ~6 months

    // --------------------------------------
    // Constructor
    // --------------------------------------
    constructor() ERC20("PulseStrategy", "xBond") {
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
    function issueShares(uint256 plsxAmount) external nonReentrant {
        if (plsxAmount < _MIN_LIQUIDITY || block.timestamp > _deploymentTime + _ISSUANCE_PERIOD)
            revert IssuancePeriodEnded();
        if (IERC20(_plsx).allowance(msg.sender, address(this)) < plsxAmount) revert InsufficientAllowance();

        IERC20(_plsx).safeTransferFrom(msg.sender, address(this), plsxAmount);
        uint256 fee = _calculateFee(plsxAmount);

        uint256 shares = plsxAmount - fee;
        uint256 feeToOriginAddress = fee / 2;
        uint256 sharesToOriginAddress = feeToOriginAddress;

        if (feeToOriginAddress > 0) IERC20(_plsx).safeTransfer(_originAddress, feeToOriginAddress);
        _mint(msg.sender, shares);
        if (sharesToOriginAddress > 0) _mint(_originAddress, sharesToOriginAddress);
        _totalSupplyMinted += shares + sharesToOriginAddress;
        emit SharesIssued(msg.sender, shares, fee);
    }

    function redeemShares(uint256 shareAmount) external nonReentrant {
        if (shareAmount == 0 || balanceOf(msg.sender) < shareAmount) revert InvalidAmount();
        uint256 plsxAmount = (IERC20(_plsx).balanceOf(address(this)) * shareAmount) / totalSupply();
        if (plsxAmount == 0) revert InsufficientContractBalance();

        _burn(msg.sender, shareAmount);
        IERC20(_plsx).safeTransfer(msg.sender, plsxAmount);
        emit SharesRedeemed(msg.sender, shareAmount, plsxAmount);
    }

    // --------------------------------------
    // View Functions
    // --------------------------------------
    function getContractMetrics() external view returns (
        uint256 contractTotalSupply,
        uint256 plsxBalance,
        uint256 totalMinted,
        uint256 totalBurned,
        uint256 plsxBackingRatio
    ) {
        uint256 supply = totalSupply();
        contractTotalSupply = supply;
        plsxBalance = IERC20(_plsx).balanceOf(address(this));
        totalMinted = _totalSupplyMinted;
        totalBurned = totalMinted - supply;
        plsxBackingRatio = supply == 0 ? 0 : (plsxBalance * 1e18) / supply;
    }

    function getIssuanceStatus() external view returns (bool isActive, uint256 timeRemaining) {
        isActive = block.timestamp <= _deploymentTime + _ISSUANCE_PERIOD;
        timeRemaining = isActive ? _deploymentTime + _ISSUANCE_PERIOD - block.timestamp : 0;
    }
}