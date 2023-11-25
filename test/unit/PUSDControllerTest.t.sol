// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployPUSD, PUSDController, PUSD, HelperConfig} from "../../script/DeployPUSD.s.sol";
import {FlashOperations} from "../../src/FlashOperations.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {FlashloanReceiverMock, BadFlashloanReceiverMock} from "../mocks/FlashloanReceiverMock.sol";

contract PUSDControllerTest is Test {
    DeployPUSD deployer;
    PUSD pUSDToken;
    PUSDController controller;
    HelperConfig config;

    address public weth;
    address public wbtc;
    address public wethUSDPriceFeed;
    address public wbtcUSDPriceFeed;

    address public owner = address(1);
    address public feeRecipient = address(2);
    address public user = address(3);
    uint256 public wethDepositAmount = 3 ether; // 3 ETH
    uint256 public wbtcDepositAmount = 10e8; // 10 WBTC
    uint256 public mintAmount = 1000 ether; // 1000 USD = 1000 PUSD

    function setUp() public {
        deployer = new DeployPUSD();
        (pUSDToken, controller, config) = deployer.run();
        (weth, wbtc, wethUSDPriceFeed, wbtcUSDPriceFeed, ) = config
            .activeConfig();
    }

    // ************************ //
    //    Correct deployment    //
    // ************************ //

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testPUSDTokenAddressSet() public {
        assertEq(address(controller.PUSDToken()), address(pUSDToken));
    }

    function testOwnerAddressSet() public {
        assertEq(address(controller.owner()), owner);
    }

    function testFeeRecipientAddressSet() public {
        assertEq(address(controller.feeRecipient()), feeRecipient);
    }

    function testRevertIfFeeRecipientIsZeroAddress() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUSDPriceFeed);
        priceFeedAddresses.push(wbtcUSDPriceFeed);
        vm.expectRevert(FlashOperations.InvalidFeeRecipient.selector);
        new PUSDController(
            address(pUSDToken),
            owner,
            address(0),
            tokenAddresses,
            priceFeedAddresses
        );
    }

    function testRevertIfArrayMismatch() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(wbtc);
        priceFeedAddresses.push(wethUSDPriceFeed);
        vm.expectRevert(PUSDController.ArrayMismatch.selector);
        new PUSDController(
            address(pUSDToken),
            owner,
            feeRecipient,
            tokenAddresses,
            priceFeedAddresses
        );
    }

    function testRevertIfDuplicateTokenInArray() public {
        tokenAddresses.push(weth);
        tokenAddresses.push(weth);
        priceFeedAddresses.push(wethUSDPriceFeed);
        priceFeedAddresses.push(wbtcUSDPriceFeed);
        vm.expectRevert(
            abi.encodeWithSelector(PUSDController.AlreadyAllowed.selector, weth)
        );
        new PUSDController(
            address(pUSDToken),
            owner,
            feeRecipient,
            tokenAddresses,
            priceFeedAddresses
        );
    }

    function testTokensAndPriceFeedAreSetCorrectly() public {
        assertEq(controller.getCollateralTokensList().length, 2);
        assertEq(controller.getTokenPriceFeed(weth), wethUSDPriceFeed);
        assertEq(controller.getTokenPriceFeed(wbtc), wbtcUSDPriceFeed);
    }

    // *********************************** //
    //    Deposit Collateral & Mint PUSD    //
    // *********************************** //

    function testRevertIfDepositZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(PUSDController.InvalidAmount.selector);
        controller.deposit(weth, msg.sender, 0);
    }

    function testRevertNotAllowedCollateral() public {
        ERC20Mock token = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.NotAllowedCollateral.selector,
                token
            )
        );
        controller.deposit(address(token), msg.sender, wethDepositAmount);
    }

    function testRevertIfUserDidNotApprove() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        vm.expectRevert();
        controller.deposit(weth, user, wethDepositAmount);
    }

    function testDepositCorrectAmountAndSendFunds() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.deposit(weth, user, wethDepositAmount);
        assertEq(
            controller.getUserCollateralAmount(user, weth),
            wethDepositAmount
        );
        assertEq(
            ERC20Mock(weth).balanceOf(address(controller)),
            wethDepositAmount
        );
        vm.stopPrank();
    }

    function testRevertIfMintWithoutCollateralDeposited() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.BelowMinHealthFactor.selector,
                0
            )
        );
        controller.mintPUSD(mintAmount);
        vm.stopPrank();
    }

    function testRevertIfBelowMinHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.deposit(weth, user, wethDepositAmount);
        uint256 collateralValue = controller.getUSDAmount(
            weth,
            wethDepositAmount
        );
        uint256 mintPUSDAmount = collateralValue;
        uint256 expectedHealthFactor = (collateralValue *
            controller.PRECISION()) / (mintPUSDAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.BelowMinHealthFactor.selector,
                expectedHealthFactor
            )
        );
        // Try mint a very amount of PUSD equivalent to collateral value in USD => user health factor will be below minimum
        controller.mintPUSD(mintPUSDAmount);
    }

    function testMintCorrectPUSDAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.deposit(weth, user, wethDepositAmount);
        controller.mintPUSD(mintAmount);
        (uint256 userMintedPUSD, ) = controller.getUserData(user);
        assertEq(userMintedPUSD, mintAmount);
        assertEq(pUSDToken.balanceOf(user), mintAmount);
    }

    function testCanDepositAndMintPUSDAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.depositAndMint(weth, wethDepositAmount, mintAmount);
        (uint256 userMintedPUSD, ) = controller.getUserData(user);
        assertEq(
            controller.getUserCollateralAmount(user, weth),
            wethDepositAmount
        );
        assertEq(userMintedPUSD, mintAmount);
        assertEq(
            ERC20Mock(weth).balanceOf(address(controller)),
            wethDepositAmount
        );
        assertEq(pUSDToken.balanceOf(user), mintAmount);
    }

    // ************************* //
    //    withdraw Collateral    //
    // ************************* //

    modifier depositCollateral(address collateral, uint256 amount) {
        vm.startPrank(user);
        ERC20Mock(collateral).mint(user, amount);
        ERC20Mock(collateral).approve(address(controller), amount);
        controller.deposit(collateral, user, amount);
        _;
    }

    modifier depositAndMintCollateral(address collateral) {
        uint256 _depositAmount = collateral == weth
            ? wethDepositAmount
            : wbtcDepositAmount;
        vm.startPrank(user);
        ERC20Mock(collateral).mint(user, _depositAmount);
        ERC20Mock(collateral).approve(address(controller), _depositAmount);
        controller.depositAndMint(collateral, _depositAmount, mintAmount);
        _;
    }

    function testRevertIfCollateralNotAllowed()
        public
        depositAndMintCollateral(weth)
    {
        ERC20Mock token = new ERC20Mock();
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.NotAllowedCollateral.selector,
                address(token)
            )
        );
        controller.withdraw(address(token), wethDepositAmount);
    }

    function testRevertIfWithdrawMoreThanDeposit()
        public
        depositCollateral(weth, wethDepositAmount)
    {
        vm.expectRevert();
        controller.withdraw(weth, 2 * wethDepositAmount);
    }

    function testRevertIfWithdrawBreaksHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        vm.expectRevert();
        controller.withdraw(weth, wethDepositAmount);
    }

    function testCanWithdrawWhenDidNotMintPUSD()
        public
        depositCollateral(weth, wethDepositAmount)
    {
        uint256 userBeforeBalance = ERC20Mock(weth).balanceOf(user);
        controller.withdraw(weth, wethDepositAmount);
        uint256 userAfterBalance = ERC20Mock(weth).balanceOf(user);
        assertEq(userAfterBalance, userBeforeBalance + wethDepositAmount);
        assertEq(controller.getUserCollateralAmount(user, weth), 0);
    }

    function testCanWithdrawWhenNotBreakingHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        uint256 userBeforeBalance = ERC20Mock(weth).balanceOf(user);
        // calculate amount to withdraw while not breaking health factor
        // choose amount that make HF equal 3e18
        uint256 withdrawAmount = (wethDepositAmount * 1e18) / (3e18);
        uint256 expectedFinalCollateralAmount = controller
            .getUserCollateralAmount(user, weth) - withdrawAmount;
        controller.withdraw(weth, withdrawAmount);
        assertEq(
            ERC20Mock(weth).balanceOf(user),
            userBeforeBalance + withdrawAmount
        );
        assertEq(
            controller.getUserCollateralAmount(user, weth),
            expectedFinalCollateralAmount
        );
    }

    // ********************* //
    //    Burn Collateral    //
    // ********************* //

    function testRevertIfBurnMoreThanBalance()
        public
        depositAndMintCollateral(weth)
    {
        vm.expectRevert();
        controller.burnPUSD(2 * mintAmount);
    }

    function testRevertIfNotApprovedPUSDTransfer()
        public
        depositAndMintCollateral(weth)
    {
        vm.expectRevert();
        controller.burnPUSD(mintAmount);
    }

    function testCanBurnPUSDMinted() public depositAndMintCollateral(weth) {
        uint256 burnAmount = mintAmount / 2;
        pUSDToken.approve(address(controller), burnAmount);
        (uint256 userPUSDMintedBefore, ) = controller.getUserData(user);
        uint256 userPUSDBeforeBalance = pUSDToken.balanceOf(user);
        uint256 pUSDTokenTotalSupplyBefore = pUSDToken.totalSupply();
        controller.burnPUSD(burnAmount);
        (uint256 userPUSDMintedAfter, ) = controller.getUserData(user);
        assertEq(pUSDToken.balanceOf(user), userPUSDBeforeBalance - burnAmount);
        assertEq(userPUSDMintedAfter, userPUSDMintedBefore - burnAmount);
        // check that the amount was burned
        assertEq(
            pUSDToken.totalSupply(),
            pUSDTokenTotalSupplyBefore - burnAmount
        );
    }

    // ************************** //
    //    burnAndWithdraw test    //
    // ************************** //

    function testRevertIfBurnAndWithdrawBreaksHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        uint256 pUSDBurnAmount = mintAmount / 4;
        uint256 withdrawAmount = (wethDepositAmount * 90) / 100;
        uint256 collateralValue = controller.getUSDAmount(
            weth,
            wethDepositAmount - withdrawAmount
        );
        uint256 remainingMintedAmount = mintAmount - pUSDBurnAmount;
        uint256 expectedHealthFactor = (collateralValue * 1e18) /
            (remainingMintedAmount);
        pUSDToken.approve(address(controller), pUSDBurnAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.BelowMinHealthFactor.selector,
                expectedHealthFactor
            )
        );
        controller.burnAndWithdraw(weth, withdrawAmount, pUSDBurnAmount);
    }

    function testCanBurnAndWithdrawWhenNotBreakingHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        uint256 pUSDBurnAmount = mintAmount / 2;
        uint256 withdrawAmount = wethDepositAmount / 2;
        pUSDToken.approve(address(controller), pUSDBurnAmount);
        controller.burnAndWithdraw(weth, withdrawAmount, pUSDBurnAmount);

        (uint256 userMintedPUSD, ) = controller.getUserData(user);
        uint256 expectedCollateralAmount = wethDepositAmount / 2;
        uint256 actualCollateralAmount = controller.getUserCollateralAmount(
            user,
            weth
        );
        assertEq(actualCollateralAmount, expectedCollateralAmount);
        assertEq(userMintedPUSD, mintAmount - pUSDBurnAmount);
    }

    // ******************** //
    //    liquidate test    //
    // ******************** //

    function testRevertIfLiquidateHealthyUser()
        public
        depositAndMintCollateral(weth)
    {
        address liquidator = address(2);
        vm.startPrank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.InvalidLiquidation.selector,
                user
            )
        );
        controller.liquidate(user, weth, mintAmount);
    }

    function testRevertIfInsufficientCollateralBalance()
        public
        depositAndMintCollateral(weth)
    {
        address liquidator = address(2);
        vm.startPrank(liquidator);
        MockV3Aggregator wethPriceFeedMock = MockV3Aggregator(wethUSDPriceFeed);
        // Drop ETH/USD price to simulate user getting below health factor
        wethPriceFeedMock.updateAnswer(100e8);
        uint256 userCollateralAmount = controller.getUserCollateralAmount(
            user,
            weth
        );
        uint256 pUSDAmountToLiquidate = controller.getUSDAmount(
            weth,
            userCollateralAmount + 0.1e18
        );
        vm.expectRevert(PUSDController.InsufficientCollateralBalance.selector);
        controller.liquidate(user, weth, pUSDAmountToLiquidate);
    }

    function testCanLiquidateUnhealthyUser()
        public
        depositAndMintCollateral(weth)
    {
        address liquidator = address(2);
        vm.startPrank(liquidator);

        // Mint PUSD token to liquidator in order to repay user debt
        ERC20Mock(wbtc).mint(liquidator, 10e8);
        ERC20Mock(wbtc).approve(address(controller), 10e8);
        controller.depositAndMint(wbtc, 10e8, mintAmount);
        controller.mintPUSD(mintAmount);
        pUSDToken.approve(address(controller), mintAmount);

        // Drop ETH/USD price to simulate user getting below health factor
        MockV3Aggregator wethPriceFeedMock = MockV3Aggregator(wethUSDPriceFeed);
        wethPriceFeedMock.updateAnswer(500e8);
        // 1 ETH = 500 USD => userHF = (3*500*1e18)/1000 = 1.5e18 < 2e18
        uint256 userHealthFactor = controller.healthFactor(user);
        assertEq(userHealthFactor, 1.5e18);

        uint256 userCollateralAmountBefore = controller.getUserCollateralAmount(
            user,
            weth
        );
        uint256 pUSDAmountToLiquidate = mintAmount;
        uint256 collateralLiquidateAmount = controller.getTokenAmountFromUSD(
            weth,
            pUSDAmountToLiquidate
        );

        // Liquidate user
        controller.liquidate(user, weth, pUSDAmountToLiquidate);

        // Check health factor is above minimum
        userHealthFactor = controller.healthFactor(user);
        assert(userHealthFactor > controller.MIN_HEALTH_FACTOR());
        (uint256 mintedPUSD, ) = controller.getUserData(user);
        uint256 userCollateralAmountAfter = controller.getUserCollateralAmount(
            user,
            weth
        );
        assertEq(mintedPUSD, 0);
        uint256 expectedCollateralAmountDecrease = (collateralLiquidateAmount *
            (1e18 + controller.LIQUIDATION_REWARD())) / 1e18;
        assertEq(
            userCollateralAmountAfter,
            userCollateralAmountBefore - expectedCollateralAmountDecrease
        );
    }

    // ******************************** //
    //    executeFlashOperation test    //
    // ******************************** //
    FlashloanReceiverMock public receiver;
    uint256 public flashAmount = 10 ether;

    function testRevertIfFlashOpsArePaused() public {
        vm.startPrank(owner);
        controller.pauseFlashOps(true);
        vm.stopPrank();
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.FlashOpsIsPaused.selector);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfReceiverIsNotContract() public {
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.InvalidFlashOp.selector);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfZeroFlashloanAmount() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.InvalidFlashOp.selector);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            0,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfNotPUSDTokenInFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.InvalidFlashOp.selector);
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfNotAllowedTokenInFlashLoan() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        address randomERC20 = address(new ERC20Mock());
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                PUSDController.NotAllowedCollateral.selector,
                randomERC20
            )
        );
        controller.executeFlashOperation(
            receiver,
            randomERC20,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();
    }

    function testRevertIfDoesNotPayFlashMintFee() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert();
        // receiver contract will not have enough PUSD token to pay fee
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfFlashLoanCallbackReturnFalse() public {
        BadFlashloanReceiverMock badReceiver = new BadFlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.FlashOpsFailed.selector);
        // receiver contract will not have enough PUSD token to pay fee
        controller.executeFlashOperation(
            badReceiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testShouldAllowUserToFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some PUSD tokens
        vm.startPrank(address(controller));
        pUSDToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testPUSDTokenSupplyMustNotChangeOnFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some PUSD tokens
        vm.startPrank(address(controller));
        pUSDToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        uint256 beforePUSDSupply = pUSDToken.totalSupply();

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();

        uint256 afterPUSDSupply = pUSDToken.totalSupply();
        assertEq(afterPUSDSupply, beforePUSDSupply);
    }

    function testShouldSendExactFlashMintFeeAmount() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some PUSD tokens
        vm.startPrank(address(controller));
        pUSDToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        uint256 flashFeeBPS = controller.flashOpsFeeBPS();
        uint256 expectedFeeAmount = (flashAmount * flashFeeBPS) / 1e18;
        uint256 beforeRecipientBalance = pUSDToken.balanceOf(feeRecipient);

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(pUSDToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();

        uint256 afterRecipientBalance = pUSDToken.balanceOf(feeRecipient);
        assertEq(
            afterRecipientBalance,
            beforeRecipientBalance + expectedFeeAmount
        );
    }

    function testRevertIfFlashLoanAmountExceedCollateralBalance()
        public
        depositCollateral(weth, 5 ether)
    {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some weth tokens
        ERC20Mock(weth).mint(address(receiver), 1 ether);

        vm.startPrank(user);
        vm.expectRevert(FlashOperations.AmountExceedsBalance.selector);
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();
    }

    function testRevertIfDoesNotPayFlashLoanFee()
        public
        depositCollateral(weth, 20 ether)
    {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert();
        // receiver contract will not have enough WETH to pay fee
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();
    }

    function testShouldAllowUserToFlashLoan()
        public
        depositCollateral(weth, 20 ether)
    {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some weth tokens
        ERC20Mock(weth).mint(address(receiver), 1 ether);

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();
    }

    function testCollateralBalanceMustNotDecreaseOnFlashLoan()
        public
        depositCollateral(weth, 20 ether)
    {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some weth tokens
        ERC20Mock(weth).mint(address(receiver), 1 ether);
        uint256 beforeControllerWethBalance = ERC20Mock(weth).balanceOf(
            address(controller)
        );

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();

        uint256 afterControllerWethBalance = ERC20Mock(weth).balanceOf(
            address(controller)
        );
        assertGe(afterControllerWethBalance, beforeControllerWethBalance);
    }

    function testShouldSendExactFlashLoanFeeAmount()
        public
        depositCollateral(weth, 20 ether)
    {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(pUSDToken),
            weth,
            wbtc
        );

        // mint receiver contract some weth tokens
        ERC20Mock(weth).mint(address(receiver), 1 ether);

        uint256 flashFeeBPS = controller.flashOpsFeeBPS();
        uint256 expectedFeeAmount = (flashAmount * flashFeeBPS) / 1e18;
        uint256 beforeRecipientBalance = ERC20Mock(weth).balanceOf(
            feeRecipient
        );

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            weth,
            flashAmount,
            "",
            FlashOperations.FlashOperationType.LOAN
        );
        vm.stopPrank();

        uint256 afterRecipientBalance = ERC20Mock(weth).balanceOf(feeRecipient);
        assertEq(
            afterRecipientBalance,
            beforeRecipientBalance + expectedFeeAmount
        );
    }

    // ********************* //
    //    Owner Functions    //
    // ********************* //

    function testRevertIfNewFeeRecipientIsZeroAddress() public {
        address newRecipient = address(0);
        vm.startPrank(owner);
        vm.expectRevert(FlashOperations.InvalidFeeRecipient.selector);
        controller.setFeeRecipient(newRecipient);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetFeeRecipient() public {
        address newRecipient = address(42);
        vm.startPrank(user);
        vm.expectRevert(); // only owner
        controller.setFeeRecipient(newRecipient);
        vm.stopPrank();

        vm.startPrank(owner);
        controller.setFeeRecipient(newRecipient);
        assertEq(controller.feeRecipient(), newRecipient);
        vm.stopPrank();
    }

    function testRevertIfNewFeeBPSIsAboveMaxBound() public {
        uint256 newFeeBPS = 1e17; // 10%
        vm.startPrank(owner);
        vm.expectRevert(FlashOperations.InvalidFeeBPS.selector);
        controller.setFlashOpsFee(newFeeBPS);
        vm.stopPrank();
    }

    function testOnlyOwnerCanSetFeeBPS() public {
        uint256 newFeeBPS = 1e15; // 0.1%
        vm.startPrank(user);
        vm.expectRevert();
        controller.setFlashOpsFee(newFeeBPS);
        vm.stopPrank();

        vm.startPrank(owner);
        controller.setFlashOpsFee(newFeeBPS);
        assertEq(controller.flashOpsFeeBPS(), newFeeBPS);
        vm.stopPrank();
    }

    function testOnlyOwnerCanPauseFlashOperations() public {
        vm.startPrank(user);
        vm.expectRevert();
        controller.pauseFlashOps(true);
        vm.stopPrank();

        vm.startPrank(owner);
        controller.pauseFlashOps(true);
        assertEq(controller.flashOpsPaused(), true);
        vm.stopPrank();
    }

    // *************************************** //
    //    HF & collateral value calculation    //
    // *************************************** //

    function testHealthFactorIsMaxWhenUserHasNotMinted()
        public
        depositCollateral(weth, wethDepositAmount)
    {
        (uint256 userPUSDMinted, ) = controller.getUserData(user);
        uint256 healthFactor = controller.healthFactor(user);
        assertEq(userPUSDMinted, 0);
        assertEq(healthFactor, type(uint256).max);
    }

    function testCalculateCorrectHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        (uint256 userPUSDMinted, uint256 collateralUsdValue) = controller
            .getUserData(user);
        uint256 expectedUserHF = (collateralUsdValue * 1e18) / userPUSDMinted;
        uint256 healthFactor = controller.healthFactor(user);
        assertEq(healthFactor, expectedUserHF);
    }

    function testCalculateCorrectCollateralUsdValue()
        public
        depositCollateral(weth, wethDepositAmount)
        depositCollateral(wbtc, wbtcDepositAmount)
    {
        uint256 wethValueInUsd = controller.getUSDAmount(
            weth,
            wethDepositAmount
        );
        uint256 wbtcValueInUsd = controller.getUSDAmount(
            wbtc,
            wbtcDepositAmount
        );
        uint256 expectedCollateralUsdValue = wethValueInUsd + wbtcValueInUsd;
        uint256 userCollateralValueInUsd = controller.getUserCollateralValue(
            user
        );
        assertEq(userCollateralValueInUsd, expectedCollateralUsdValue);
    }

    // ********************* //
    //    Price feed test    //
    // ********************* //

    function testReturnCorrectUsdAmount() public {
        // Note returned USD amount from getUSDAmount are always scaled by 1e18
        // Test WETH token
        // we set 1 weth = 2000 USD
        // So for 10ETH we should get 20000USD
        uint256 ethAmount = 10 ether;
        uint256 expectedUSDAmount = 20000e18;
        uint256 returnedAmount = controller.getUSDAmount(weth, ethAmount);
        assertEq(returnedAmount, expectedUSDAmount);

        // Test WBTC token
        // we set 1 wbtc = 1000 USD
        // So for 10 WBTC we should get 10000USD
        uint256 btcAmount = 10e8; // WBTC has 8 decimals
        expectedUSDAmount = 10000e18;
        returnedAmount = controller.getUSDAmount(wbtc, btcAmount);
        assertEq(returnedAmount, expectedUSDAmount);
    }

    function testReturnCorrectCollateralAmount() public {
        // Test WETH token
        // we set 1 weth = 2000 USD
        // So for 10000 USD we should get 5 ETH
        uint256 usdAmount = 10000e18;
        uint256 expectedWethAmount = 5 ether;
        uint256 returnedAmount = controller.getTokenAmountFromUSD(
            weth,
            usdAmount
        );
        assertEq(returnedAmount, expectedWethAmount);

        // Test WBTC token
        // we set 1 wbtc = 1000 USD
        // So for 500 USD we should get 0.5 WBTC = 5e7 WBTC
        usdAmount = 500e18;
        uint256 expectedWbtcAmount = 5e7; // 0.5 WBTC
        returnedAmount = controller.getTokenAmountFromUSD(wbtc, usdAmount);
        assertEq(returnedAmount, expectedWbtcAmount);
    }
}
