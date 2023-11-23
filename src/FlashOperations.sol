// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {TokenHelper} from "./libraries/TokenHelper.sol";
import "./interfaces/IFlashloanReceiver.sol";
import "./interfaces/IPUSD.sol";

/// @title Flash Operations logic
/// @author kaymen99
/// @notice Contract for executing flash operations including flash mint and flash loan
/// @dev Will allow users to perform flash mint of PUSD token or to flashloan collateral tokens kept in the controller contract.
abstract contract FlashOperations {
    // can flashmint PUSD token or flashloan allowed collateral tokens
    /// @dev Enum defining the types of flash operations: MINT or LOAN
    enum FlashOperationType {
        MINT,
        LOAN
    }

    /// @dev Maximum fee for flash operations
    uint256 public constant MAX_FEE = 1e16; // 1%

    /// @dev Address that will receive fees on flash operations, set by owner
    address public feeRecipient;
    /// @dev Flag indicating whether flash operations are paused
    bool public flashOpsPaused;
    /// @dev Maximum fee percentage for flash operations, set by owner
    uint256 public flashOpsFeeBPS = 3e15; // 0.3%

    /// @dev Event emitted when the fee recipient is set
    event SetFeeRecipient(
        address indexed oldRecipient,
        address indexed newRecipient
    );
    /// @dev Event emitted when the flash operation fee is set
    event SetFlashOpsFee(uint256 indexed oldFeeBPS, uint256 indexed newFeeBPS);
    /// @dev Event emitted when flash operations are paused or unpaused
    event FlashOpsPaused(bool paused);

    error FlashOpsIsPaused();
    error InvalidFlashOp();
    error AmountExceedsBalance();
    error FlashOpsFailed();
    error PUSDTotalSupplyHasChanged();
    error TokenBalanceDecrease();
    error InvalidFeeRecipient();
    error InvalidFeeBPS();

    constructor(address _feeRecipient) {
        _setFeeRecipient(_feeRecipient);
    }

    // ***************** //
    //  Public/external  //
    // ***************** //

    /// @notice Allow users to execute flash operations.
    /// @dev callable by anyone, flashOps must not be paused and receiver must implement IFlashloanReceiver.
    /// @param receiver contract that will receive flash ops funds
    /// @param token address of flashloaned token, set to PUSD address for flashMint.
    /// @param amount amount of token desired, must be non zero.
    /// @param params user-defined parameters.
    /// @param opType type of flash operation either MINT or LOAN
    /// @return boolean value: true for success, otherwise false
    function executeFlashOperation(
        IFlashloanReceiver receiver,
        address token,
        uint256 amount,
        bytes calldata params,
        FlashOperationType opType
    ) external returns (bool) {
        if (flashOpsPaused) revert FlashOpsIsPaused();
        if (address(receiver).code.length == 0 || amount == 0)
            revert InvalidFlashOp();
        if (opType == FlashOperationType.MINT) {
            if (token != address(PUSDToken())) revert InvalidFlashOp();
            _runFlashMint(receiver, amount, params);
        } else {
            allowedToken(token);
            _runFlashLoan(receiver, token, amount, params);
        }
        return true;
    }

    /// @notice internal function for flashMint logic
    /// @dev mint PUSD amount to user and burn it after flashOps ends, must provide exact fee amount
    /// @dev PUSD token total supply must not change during flashlaon
    /// @param receiver contract that will receive flash ops funds
    /// @param amount amount of token desired, must be non-zero.
    /// @param params user-defined parameters.
    function _runFlashMint(
        IFlashloanReceiver receiver,
        uint256 amount,
        bytes calldata params
    ) internal {
        IPUSD token = PUSDToken();
        uint256 pUSDSupplyBefore = token.totalSupply();
        uint256 fee = (amount * flashOpsFeeBPS) / 1e18;

        // mint PUSD token amount to
        token.mint(address(receiver), amount);

        bool success = receiver.onFlashLoan(
            msg.sender,
            address(token),
            amount,
            fee,
            params
        );
        if (!success) revert FlashOpsFailed();

        // transfer minted amount plus fee from user to fee recipient
        // saves gas by avoiding double transfer operations
        token.transferFrom(address(receiver), feeRecipient, amount + fee);

        // fee recipient keeps only fee, burn remaining amount
        token.burnFrom(feeRecipient, amount);

        // check that PUSD total supply did not change
        uint256 pUSDSupplyAfter = token.totalSupply();
        if (pUSDSupplyAfter != pUSDSupplyBefore)
            revert PUSDTotalSupplyHasChanged();
    }

    /// @notice internal function for flashLoan logic
    /// @dev must provide exact fee amount
    /// @dev will revert if amount exceeds collateral balance or if balance decreases after flashloan
    /// @dev PUSD token total supply must not change during flashlaon
    /// @param receiver contract that will receive flash ops funds
    /// @param token address of flashloaned token.
    /// @param amount amount of token desired, must be non-zero.
    /// @param params user-defined parameters.
    function _runFlashLoan(
        IFlashloanReceiver receiver,
        address token,
        uint256 amount,
        bytes calldata params
    ) internal {
        uint256 balanceBefore = TokenHelper.balanceOf(token, address(this));
        if (amount > balanceBefore) revert AmountExceedsBalance();
        uint256 fee = (amount * flashOpsFeeBPS) / 1e18;

        // mint PUSD token amount to
        TokenHelper.transferToken(
            token,
            address(this),
            address(receiver),
            amount
        );

        bool success = receiver.onFlashLoan(
            msg.sender,
            address(token),
            amount,
            fee,
            params
        );
        if (!success) revert FlashOpsFailed();

        // transfer loaned amount back from user to controller
        TokenHelper.transferToken(
            token,
            address(receiver),
            address(this),
            amount + fee
        );

        // transfer fee to fee recipient
        TokenHelper.transferToken(token, address(this), feeRecipient, fee);

        // check that internal token balance did not decrease
        uint256 balanceAfter = TokenHelper.balanceOf(token, address(this));
        if (balanceAfter < balanceBefore) revert TokenBalanceDecrease();
    }

    /// @notice internal function to set new fee recipient
    function _setFeeRecipient(address recipient) internal {
        if (recipient == address(0)) revert InvalidFeeRecipient();
        emit SetFeeRecipient(feeRecipient, recipient);
        feeRecipient = recipient;
    }

    /// @notice internal function for set new fee
    function _setFlashOpsFee(uint256 newFee) internal {
        if (newFee > MAX_FEE) revert InvalidFeeBPS();
        emit SetFlashOpsFee(flashOpsFeeBPS, newFee);
        flashOpsFeeBPS = newFee;
    }

    /// @notice internal function to change paused state
    function _pauseFlashOps(bool pause) internal {
        flashOpsPaused = pause;
        emit FlashOpsPaused(pause);
    }

    /// @notice should revert if token is not allowed
    function allowedToken(address token) public virtual {}

    /// @notice Function to get the PUSD token
    function PUSDToken() public view virtual returns (IPUSD) {}
}
