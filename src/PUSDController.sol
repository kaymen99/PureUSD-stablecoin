// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {FlashOperations} from "./FlashOperations.sol";
import {ChainlinkOracle} from "./libraries/ChainlinkOracle.sol";
import {TokenHelper} from "./libraries/TokenHelper.sol";
import "./interfaces/IPUSD.sol";

contract PUSDController is Ownable, FlashOperations {
    using ChainlinkOracle for AggregatorV3Interface;

    // *************** //
    //    Variables    //
    // *************** //

    // default precision used for price calculations
    uint256 public constant PRECISION = 1e18;
    // By default up to 50% of collateral can be liquidated
    uint256 public constant DEFAULT_LIQUIDATION_FACTOR = 0.5e18;
    // 5% of collateral given to liquidator as bonus
    uint256 public constant LIQUIDATION_REWARD = 0.05e18;
    // Collateral value must be equal 1.5x the value of PUSD minted
    // Using 150% overcollateralization
    uint256 public constant MIN_HEALTH_FACTOR = 1.5e18;
    // Below 135% collateralization ratio full liquidation is allowed
    uint256 public constant LIQUIDATION_CLOSE_FACTOR = 1.35e18;

    IPUSD private immutable pUSD;

    mapping(address token => address priceFeedAddress)
        private allowedCollaterals;
    address[] private allowedCollateralsList;

    mapping(address user => mapping(address token => uint256 amount)) collateralBalances;
    mapping(address user => uint256 amount) mintedBalances;

    // ************ //
    //    Errors    //
    // ************ //
    error InvalidAmount();
    error AddressZero();
    error ArrayMismatch();
    error NotAllowedCollateral(address collateral);
    error BelowMinHealthFactor(uint256 healthFactor);
    error MintFailed();
    error InvalidLiquidation(address user);
    error InsufficientCollateralBalance();
    error AlreadyAllowed(address collateral);

    // ************ //
    //    Events    //
    // ************ //

    event CollateralDeposit(address recipient, address token, uint256 amount);
    event WithdrawCollateral(
        address from,
        address to,
        address token,
        uint256 amount
    );
    event AllowCollateral(address collateral);

    /**
     * @dev Constructor for the main Pool contract.
     * @param pUSDTokenAddress The address of the pUSD token.
     * @param admin The address of the contract owner.
     * @param _feeRecipient The address to receive flash fees collected by the pool.
     * @param collaterals An array of supported collateral token addresses (WETH/WBTC).
     * @param priceFeeds An array of corresponding Chainlink price feed addresses for each collateral.
     */
    constructor(
        address pUSDTokenAddress,
        address admin,
        address _feeRecipient,
        address[] memory collaterals,
        address[] memory priceFeeds
    ) Ownable(admin) FlashOperations(_feeRecipient) {
        if (collaterals.length != priceFeeds.length) revert ArrayMismatch();
        for (uint256 i = 0; i < collaterals.length; ) {
            _allowCollateral(collaterals[i], priceFeeds[i]);
            unchecked {
                i++;
            }
        }
        pUSD = IPUSD(pUSDTokenAddress);
    }

    // ***************** //
    //  Public/external  //
    // ***************** //

    /// @notice Deposit collateral ERC20 tokens
    /// @dev Can only deposit WETH or WBTC, user must approve token transfer
    /// @param token address of collateral token deposited (weth/wbtc)
    /// @param recipient address which gets deposited colleteral
    /// @param amount amount of collateral to deposit
    function deposit(address token, address recipient, uint256 amount) public {
        if (amount == 0) revert InvalidAmount();
        allowedToken(token);
        unchecked {
            // cannot overflow because transfer will revert
            collateralBalances[recipient][token] += amount;
        }
        TokenHelper.transferToken(token, msg.sender, address(this), amount);
        emit CollateralDeposit(recipient, token, amount);
    }

    /// @notice Mints PUSD token to caller
    /// @dev Must have collateral deposited first
    /// @param amount amount of PUSD token to mint
    function mintPUSD(uint256 amount) public {
        unchecked {
            // cannot overflow because of HF check
            mintedBalances[msg.sender] += amount;
        }
        _revertIfBelowHealthFactor(msg.sender);
        if (!pUSD.mint(msg.sender, amount)) revert MintFailed();
    }

    /// @notice Deposit collateral and Mints PUSD token to caller
    /// @param collateralToken address of collateral token deposited (weth/wbtc)
    /// @param collateralAmount amount of collateral to deposit
    /// @param pUSDAmount amount of PUSD token to mint
    function depositAndMint(
        address collateralToken,
        uint256 collateralAmount,
        uint256 pUSDAmount
    ) external {
        deposit(collateralToken, msg.sender, collateralAmount);
        mintPUSD(pUSDAmount);
    }

    /// @notice Withdraw collateral back to caller
    /// @dev reverts if caller gets below MIN_HEALTH_FACTOR
    /// @param token address of collateral token withdrawn (weth/wbtc)
    /// @param amount amount of collateral to withdraw
    function withdraw(address token, uint256 amount) public {
        _withdraw(msg.sender, msg.sender, token, amount);
        _revertIfBelowHealthFactor(msg.sender);
    }

    /// @notice Burns PUSD token from caller
    /// @dev Must approve PUSD token to address(this)
    /// @param amount amount of PUSD token to burn
    function burnPUSD(uint256 amount) external {
        _burnPUSD(msg.sender, amount);
    }

    /// @notice Burns PUSD token and withdraws collateral back to caller
    /// @param collateralToken address of collateral token to withdraw (weth/wbtc)
    /// @param collateralAmount amount of collateral to withdraw
    /// @param pUSDAmount amount of PUSD token to burn
    function burnAndWithdraw(
        address collateralToken,
        uint256 collateralAmount,
        uint256 pUSDAmount
    ) external {
        _burnPUSD(msg.sender, pUSDAmount);
        withdraw(collateralToken, collateralAmount);
    }

    /// @notice Burns PUSD token and withdraws collateral back to caller
    /// @dev allow liquidation of unhealthy users, liquidator pays back user PUSD debt and receive collateral amount plus liquidation bonus
    /// @param user address of user being liquidated
    /// @param collateral address of collateral token to liquidate (weth/wbtc)
    /// @param pUSDToLiquidate amount of PUSD token to pay
    function liquidate(
        address user,
        address collateral,
        uint256 pUSDToLiquidate
    ) external {
        uint256 userHealthFactor = _calculateHealthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR)
            revert InvalidLiquidation(user);

        // If user HF above 135% ratio then can liquidated up to 50% of PUSD
        // else all user minted PUSD can be liquidated
        uint256 maxPUSDToLiquidate = userHealthFactor >=
            LIQUIDATION_CLOSE_FACTOR
            ? (mintedBalances[user] * DEFAULT_LIQUIDATION_FACTOR) / PRECISION
            : mintedBalances[user];
        pUSDToLiquidate = pUSDToLiquidate > maxPUSDToLiquidate
            ? maxPUSDToLiquidate
            : pUSDToLiquidate;
        // convert PUSD value to collateral amount
        uint256 collateralAmount = getTokenAmountFromUSD(
            collateral,
            pUSDToLiquidate
        );
        uint256 liquidationReward = (collateralAmount * LIQUIDATION_REWARD) /
            PRECISION;
        uint256 totalCollateralToLiquidate = collateralAmount +
            liquidationReward;
        if (totalCollateralToLiquidate > collateralBalances[user][collateral])
            revert InsufficientCollateralBalance();
        _withdraw(user, msg.sender, collateral, totalCollateralToLiquidate);
        _burnPUSD(user, pUSDToLiquidate);

        if (_calculateHealthFactor(user) <= userHealthFactor)
            revert InvalidLiquidation(user);
    }

    // ************* //
    //    Getters    //
    // ************* //

    /// @notice Returns list of all allowed collateral tokens
    function getCollateralTokensList()
        external
        view
        returns (address[] memory)
    {
        return allowedCollateralsList;
    }

    /// @notice Gets the chainlink price feed of collateral token
    /// @param token address of collateral token
    /// @return address of collateral price feed
    function getTokenPriceFeed(address token) external view returns (address) {
        return allowedCollaterals[token];
    }

    /// @notice Gets amount of collateral token (weth/wbtc) deposited by user
    /// @param user address of user
    /// @param token address of collateral token
    /// @return amount of collateral token deposited
    function getUserCollateralAmount(
        address user,
        address token
    ) external view returns (uint256) {
        return collateralBalances[user][token];
    }

    /// @notice Gives the user minted PUSD amount and total collateral value in USD
    /// @param user address of user
    function getUserData(
        address user
    )
        external
        view
        returns (uint256 totalPUSDMinted, uint256 totalCollateralInUSD)
    {
        totalPUSDMinted = mintedBalances[user];
        totalCollateralInUSD = getUserCollateralValue(user);
    }

    /// @notice Calculates the total collateral value in USD of the user
    /// @param user address of user
    /// @return totalCollateralValueInUSD total collateral value in USD (in 18 decimals)
    function getUserCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUSD) {
        uint256 length = allowedCollateralsList.length;
        for (uint256 i; i < length; ) {
            address token = allowedCollateralsList[i];
            uint256 balance = collateralBalances[user][token];
            if (balance != 0) {
                totalCollateralValueInUSD += getUSDAmount(token, balance);
            }
            unchecked {
                i++;
            }
        }
    }

    /// @notice gets the health factor of user
    /// @param user address of user
    function healthFactor(address user) external view returns (uint256 factor) {
        return _calculateHealthFactor(user);
    }

    /// @notice Convert USD amount to collateral token amount using chainlink price feeds
    /// @param token address of colllateral token
    /// @param usdAmount amount in USD (in 18 decimals)
    /// @return value collateral amount (in token decimals)
    function getTokenAmountFromUSD(
        address token,
        uint256 usdAmount
    ) public view returns (uint256 value) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            allowedCollaterals[token]
        );
        uint256 price = priceFeed.getPrice();

        // value will be in 18 decimals
        value = (usdAmount * PRECISION) / (price * 1e10);

        // convert to token decimals
        uint8 decimals = TokenHelper.tokenDecimals(token);
        value = value / 10 ** (18 - decimals);
    }

    /// @notice Convert collateral amount to USD amount using chainlink price feeds
    /// @param token address of colllateral token
    /// @param amount amount of collateral token
    /// @return value USD amount (in 18 decimals)
    function getUSDAmount(
        address token,
        uint256 amount
    ) public view returns (uint256 value) {
        uint8 decimals = TokenHelper.tokenDecimals(token);
        uint256 amountIn18Decimals = amount * 10 ** (18 - decimals);
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            allowedCollaterals[token]
        );
        uint256 price = priceFeed.getPrice();
        value = (amountIn18Decimals * price * 1e10) / PRECISION;
    }

    function allowedToken(address token) public view override {
        if (allowedCollaterals[token] == address(0))
            revert NotAllowedCollateral(token);
    }

    function PUSDToken() public view override returns (IPUSD) {
        return pUSD;
    }

    // ******************** //
    //    Owner Functions   //
    // ******************** //

    /// @notice set new fee recipient
    /// @dev only callable by onwer
    /// @param recipient address of new recipient, must be non-zero.
    function setFeeRecipient(address recipient) external onlyOwner {
        _setFeeRecipient(recipient);
    }

    /// @notice set new flash ops fee
    /// @dev only callable by onwer
    /// @param newFee new fee percentage.
    function setFlashOpsFee(uint256 newFee) external onlyOwner {
        _setFlashOpsFee(newFee);
    }

    /// @notice change flash operations paused state
    /// @dev only callable by onwer
    /// @param pause true for paused, false otherwise.
    function pauseFlashOps(bool pause) external onlyOwner {
        _pauseFlashOps(pause);
    }

    // ************** //
    //    Internal    //
    // ************** //

    /// @notice sets new collateral price feed and add to allowed list
    /// @dev collateral token can only be allowed once
    /// @param token address of collateral token
    /// @param priceFeed address of the chainlink price feed, should be different from address(0)
    function _allowCollateral(address token, address priceFeed) internal {
        if (allowedCollaterals[token] != address(0))
            revert AlreadyAllowed(token);
        if (priceFeed == address(0)) revert AddressZero();
        allowedCollaterals[token] = priceFeed;
        allowedCollateralsList.push(token);

        emit AllowCollateral(token);
    }

    /// @notice calculate user health factor
    /// @dev health factor is the ratio between total collateral value (in USD) and total minted PUSD for a given user
    /// @param user address of the user
    /// @return factor the user health factor scaled by 1e18
    function _calculateHealthFactor(
        address user
    ) internal view returns (uint256 factor) {
        uint256 pUSDBalance = mintedBalances[user];
        if (pUSDBalance == 0) return type(uint256).max;
        uint256 collateralBalanceInUSD = getUserCollateralValue(user);
        factor = (collateralBalanceInUSD * PRECISION) / pUSDBalance;
    }

    /// @notice Perform health factor check
    /// @dev will revert if user's health factor is below min value
    /// @param user address of the user
    function _revertIfBelowHealthFactor(address user) internal view {
        uint256 _healthFactor = _calculateHealthFactor(user);
        if (_healthFactor < MIN_HEALTH_FACTOR)
            revert BelowMinHealthFactor(_healthFactor);
    }

    /// @notice withdraw collateral token
    /// @dev should be called in public function that implemented health factor check
    /// @param from address to withdraw collateral from
    /// @param to address to send collateral to
    /// @param token address of collateral token to withdraw
    /// @param amount amount of collateral token to withdraw
    function _withdraw(
        address from,
        address to,
        address token,
        uint256 amount
    ) private {
        allowedToken(token);
        collateralBalances[from][token] -= amount;
        TokenHelper.transferToken(token, address(this), to, amount);
        emit WithdrawCollateral(from, to, token, amount);
    }

    /// @notice burn PUSD token from user
    /// @dev user must have approved PUSD token transfer
    /// @param from address to burn token from
    /// @param amount amount of PUSD token to burn
    function _burnPUSD(address from, uint256 amount) private {
        if (amount != 0) {
            mintedBalances[from] -= amount;
            TokenHelper.transferToken(
                address(pUSD),
                msg.sender,
                address(this),
                amount
            );
            pUSD.burn(amount);
        }
    }
}
