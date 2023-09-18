// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ChainlinkOracle} from "./libraries/ChainlinkOracle.sol";
import {TokenHelper} from "./libraries/TokenHelper.sol";
import "./interfaces/IDSCToken.sol";

contract DSCController {
    using ChainlinkOracle for AggregatorV3Interface;

    // *************** //
    //    Variables    //
    // *************** //

    // default precision used for price calculations
    uint256 public constant PRECISION = 1e18;
    // 5% of collateral given to liquidator as bonus
    uint256 public constant LIQUIDATION_REWARD = 0.05e18;
    // Collateral value must be equal double the value of DSC minted
    // Using 200% overcollateralization
    uint256 public constant MIN_HEALTH_FACTOR = 2e18;

    IDSCToken public immutable dscToken;

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

    constructor(
        address dscTokenAddress,
        address[] memory collaterals,
        address[] memory priceFeeds
    ) {
        if (collaterals.length != priceFeeds.length) revert ArrayMismatch();
        for (uint256 i = 0; i < collaterals.length; ) {
            _allowCollateral(collaterals[i], priceFeeds[i]);
            unchecked {
                i++;
            }
        }
        dscToken = IDSCToken(dscTokenAddress);
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
        if (allowedCollaterals[token] == address(0))
            revert NotAllowedCollateral(token);
        unchecked {
            // cannot overflow because transfer will revert
            collateralBalances[recipient][token] += amount;
        }
        TokenHelper.transferERC20(token, msg.sender, address(this), amount);
        emit CollateralDeposit(recipient, token, amount);
    }

    /// @notice Mints DSC token to caller
    /// @dev Must have collateral deposited first
    /// @param amount amount of DSC token to mint
    function mintDSC(uint256 amount) public {
        unchecked {
            // cannot overflow because of HF check
            mintedBalances[msg.sender] += amount;
        }
        _revertIfBelowHealthFactor(msg.sender);
        if (!dscToken.mint(msg.sender, amount)) revert MintFailed();
    }

    /// @notice Deposit collateral and Mints DSC token to caller
    /// @param collateralToken address of collateral token deposited (weth/wbtc)
    /// @param collateralAmount amount of collateral to deposit
    /// @param dscAmount amount of DSC token to mint
    function depositAndMint(
        address collateralToken,
        uint256 collateralAmount,
        uint256 dscAmount
    ) external {
        deposit(collateralToken, msg.sender, collateralAmount);
        mintDSC(dscAmount);
    }

    /// @notice Withdraw collateral back to caller
    /// @dev reverts if caller gets below MIN_HEALTH_FACTOR
    /// @param token address of collateral token withdrawn (weth/wbtc)
    /// @param amount amount of collateral to withdraw
    function withdraw(address token, uint256 amount) public {
        _withdraw(msg.sender, msg.sender, token, amount);
        _revertIfBelowHealthFactor(msg.sender);
    }

    /// @notice Burns DSC token from caller
    /// @dev Must approve DSC token to address(this)
    /// @param amount amount of DSC token to burn
    function burnDSC(uint256 amount) external {
        _burnDSC(msg.sender, amount);
    }

    /// @notice Burns DSC token and withdraws collateral back to caller
    /// @param collateralToken address of collateral token to withdraw (weth/wbtc)
    /// @param collateralAmount amount of collateral to withdraw
    /// @param dscAmount amount of DSC token to burn
    function burnAndWithdraw(
        address collateralToken,
        uint256 collateralAmount,
        uint256 dscAmount
    ) external {
        _burnDSC(msg.sender, dscAmount);
        withdraw(collateralToken, collateralAmount);
    }

    /// @notice Burns DSC token and withdraws collateral back to caller
    /// @dev allow liquidation of unhealthy users, liquidator pays back user DSC debt and receive collateral amount plus liquidation bonus
    /// @param user address of user being liquidated
    /// @param collateral address of collateral token to liquidate (weth/wbtc)
    /// @param dscToLiquidate amount of DSC token to pay
    function liquidate(
        address user,
        address collateral,
        uint256 dscToLiquidate
    ) external {
        uint256 userHealthFactor = _calculateHealthFactor(user);
        if (userHealthFactor >= MIN_HEALTH_FACTOR)
            revert InvalidLiquidation(user);

        uint256 collateralAmount = getTokenAmountFromUSD(
            collateral,
            dscToLiquidate
        );
        uint256 liquidationReward = (collateralAmount * LIQUIDATION_REWARD) /
            PRECISION;
        uint256 totalCollateralToLiquidate = collateralAmount +
            liquidationReward;

        if (totalCollateralToLiquidate > collateralBalances[user][collateral])
            revert InsufficientCollateralBalance();
        _withdraw(user, msg.sender, collateral, totalCollateralToLiquidate);
        _burnDSC(user, dscToLiquidate);

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

    /// @notice Gives the user minted DSC amount and total collateral value in USD
    /// @param user address of user
    function getUserData(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 totalCollateralInUSD)
    {
        totalDSCMinted = mintedBalances[user];
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
    /// @dev health factor is the ratio between total collateral value (in USD) and total minted DSC for a given user
    /// @param user address of the user
    /// @return factor : health factor scaled by 1e18
    function _calculateHealthFactor(
        address user
    ) internal view returns (uint256 factor) {
        uint256 dscBalance = mintedBalances[user];
        if (dscBalance == 0) return type(uint256).max;
        uint256 collateralBalanceInUSD = getUserCollateralValue(user);
        factor = (collateralBalanceInUSD * PRECISION) / dscBalance;
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
        if (allowedCollaterals[token] == address(0))
            revert NotAllowedCollateral(token);
        collateralBalances[from][token] -= amount;
        TokenHelper.transferERC20(token, address(this), to, amount);
        emit WithdrawCollateral(from, to, token, amount);
    }

    /// @notice burn DSC token from user
    /// @dev user must have approved DSC token transfer
    /// @param from address to burn token from
    /// @param amount amount of DSC token to burn
    function _burnDSC(address from, uint256 amount) private {
        if (amount != 0) {
            mintedBalances[from] -= amount;
            TokenHelper.transferERC20(
                address(dscToken),
                msg.sender,
                address(this),
                amount
            );
            dscToken.burn(amount);
        }
    }
}
