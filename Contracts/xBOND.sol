// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

// OpenZeppelin Imports
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title PulseStrategy
 * @notice A Decentralized PLSX Reserve, allows for issuance/redemption of xBOND. Issuance ends when max supply is reached. Issuance/redemption follow reserve ratio.
 * @dev xBOND has a 0.5% tax on transfers (0.25% burned, 0.25% to an origin Address, excluding minting/redemptions).
 */
contract PulseStrategy is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    // --------------------------------------
    // Errors
    // --------------------------------------
    error InvalidAmount();
    error ZeroAddress();
    error MaxSupplyReached();
    error InsufficientContractBalance();
    error InsufficientAllowance();

    // --------------------------------------
    // Events
    // --------------------------------------
    event SharesIssued(address indexed buyer, uint256 shares, uint256 totalFee);
    event SharesRedeemed(address indexed redeemer, uint256 shares, uint256 plsx);
    event TransferTaxApplied(address indexed from, address indexed to, uint256 amountAfterTax, uint256 xBONDToOriginAddress, uint256 burned);

    // --------------------------------------
    // State Variables
    // --------------------------------------
    uint256 private _totalSupplyMinted;

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
    uint256 private constant _MIN_TRANSFER = 10e15; // 0.01 xBOND
    uint16 private constant _BASIS_DENOMINATOR = 10000; // 10,000
    uint256 private constant _MAX_SUPPLY = 3_690_000_000_000 * 1e18; // 3,690,000,000,000 xBOND

    // --------------------------------------
    // Constructor
    // --------------------------------------
    constructor() ERC20("PulseStrategy", "xBOND") {
        _originAddress = msg.sender;
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

        if (from == address(0) || to == address(0) || from == _originAddress || to == _originAddress) {
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
        if (plsxAmount < _MIN_LIQUIDITY) revert InvalidAmount();
        if (_totalSupplyMinted >= _MAX_SUPPLY) revert MaxSupplyReached();
        if (IERC20(_plsx).allowance(msg.sender, address(this)) < plsxAmount) revert InsufficientAllowance();

        IERC20(_plsx).safeTransferFrom(msg.sender, address(this), plsxAmount);
        uint256 fee = _calculateFee(plsxAmount);
        uint256 feeToOriginAddress = fee / 2;
        uint256 userPlsxContribution = plsxAmount - fee;

        uint256 totalSupply = totalSupply();
        uint256 plsxBalance = IERC20(_plsx).balanceOf(address(this)) - plsxAmount;
        uint256 shares;
        uint256 sharesToOriginAddress;

        if (totalSupply == 0) {
            
            shares = userPlsxContribution;
            sharesToOriginAddress = feeToOriginAddress;
        } else {
            
            shares = Math.mulDiv(userPlsxContribution, totalSupply, plsxBalance, Math.Rounding.Floor);
            sharesToOriginAddress = Math.mulDiv(feeToOriginAddress, totalSupply, plsxBalance, Math.Rounding.Floor);
        }

        
        if (_totalSupplyMinted + shares + sharesToOriginAddress > _MAX_SUPPLY) revert MaxSupplyReached();

        if (feeToOriginAddress > 0) IERC20(_plsx).safeTransfer(_originAddress, feeToOriginAddress);
        _mint(msg.sender, shares);
        if (sharesToOriginAddress > 0) _mint(_originAddress, sharesToOriginAddress);
        _totalSupplyMinted += shares + sharesToOriginAddress;
        emit SharesIssued(msg.sender, shares, fee);
    }

    function redeemShares(uint256 shareAmount) external nonReentrant {
        if (shareAmount == 0 || balanceOf(msg.sender) < shareAmount) revert InvalidAmount();
        uint256 plsxAmount = Math.mulDiv(
            IERC20(_plsx).balanceOf(address(this)),
            shareAmount,
            totalSupply(),
            Math.Rounding.Floor
        );
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
        plsxBackingRatio = supply == 0 ? 0 : Math.mulDiv(plsxBalance, 1e18, supply, Math.Rounding.Floor);
    }

    function getIssuanceStatus() external view returns (bool isActive, uint256 supplyRemaining) {
        isActive = _totalSupplyMinted < _MAX_SUPPLY;
        supplyRemaining = isActive ? _MAX_SUPPLY - _totalSupplyMinted : 0;
    }
}