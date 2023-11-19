// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC, DSCController, DSCToken, HelperConfig} from "../../script/DeployDSC.s.sol";
import {FlashOperations} from "../../src/FlashOperations.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {FlashloanReceiverMock, BadFlashloanReceiverMock} from "../mocks/FlashloanReceiverMock.sol";

contract DSCControllerTest is Test {
    DeployDSC deployer;
    DSCToken dscToken;
    DSCController controller;
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
    uint256 public mintAmount = 1000 ether; // 1000 USD = 1000 DSC

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, controller, config) = deployer.run();
        (weth, wbtc, wethUSDPriceFeed, wbtcUSDPriceFeed, ) = config
            .activeConfig();
    }

    // ************************ //
    //    Correct deployment    //
    // ************************ //

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testDSCTokenAddressSet() public {
        assertEq(address(controller.DSCToken()), address(dscToken));
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
        new DSCController(
            address(dscToken),
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
        vm.expectRevert(DSCController.ArrayMismatch.selector);
        new DSCController(
            address(dscToken),
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
            abi.encodeWithSelector(DSCController.AlreadyAllowed.selector, weth)
        );
        new DSCController(
            address(dscToken),
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
    //    Deposit Collateral & Mint DSC    //
    // *********************************** //

    function testRevertIfDepositZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert(DSCController.InvalidAmount.selector);
        controller.deposit(weth, msg.sender, 0);
    }

    function testRevertNotAllowedCollateral() public {
        ERC20Mock token = new ERC20Mock();
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCController.NotAllowedCollateral.selector,
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
                DSCController.BelowMinHealthFactor.selector,
                0
            )
        );
        controller.mintDSC(mintAmount);
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
        uint256 mintDSCAmount = collateralValue;
        uint256 expectedHealthFactor = (collateralValue *
            controller.PRECISION()) / (mintDSCAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCController.BelowMinHealthFactor.selector,
                expectedHealthFactor
            )
        );
        // Try mint a very amount of DSC equivalent to collateral value in USD => user health factor will be below minimum
        controller.mintDSC(mintDSCAmount);
    }

    function testMintCorrectDSCAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.deposit(weth, user, wethDepositAmount);
        controller.mintDSC(mintAmount);
        (uint256 userMintedDSC, ) = controller.getUserData(user);
        assertEq(userMintedDSC, mintAmount);
        assertEq(dscToken.balanceOf(user), mintAmount);
    }

    function testCanDepositAndMintDSCAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).mint(user, wethDepositAmount);
        ERC20Mock(weth).approve(address(controller), wethDepositAmount);
        controller.depositAndMint(weth, wethDepositAmount, mintAmount);
        (uint256 userMintedDSC, ) = controller.getUserData(user);
        assertEq(
            controller.getUserCollateralAmount(user, weth),
            wethDepositAmount
        );
        assertEq(userMintedDSC, mintAmount);
        assertEq(
            ERC20Mock(weth).balanceOf(address(controller)),
            wethDepositAmount
        );
        assertEq(dscToken.balanceOf(user), mintAmount);
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
                DSCController.NotAllowedCollateral.selector,
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

    function testCanWithdrawWhenDidNotMintDSC()
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
        controller.burnDSC(2 * mintAmount);
    }

    function testRevertIfNotApprovedDSCTransfer()
        public
        depositAndMintCollateral(weth)
    {
        vm.expectRevert();
        controller.burnDSC(mintAmount);
    }

    function testCanBurnDSCMinted() public depositAndMintCollateral(weth) {
        uint256 burnAmount = mintAmount / 2;
        dscToken.approve(address(controller), burnAmount);
        (uint256 userDSCMintedBefore, ) = controller.getUserData(user);
        uint256 userDSCBeforeBalance = dscToken.balanceOf(user);
        uint256 dscTokenTotalSupplyBefore = dscToken.totalSupply();
        controller.burnDSC(burnAmount);
        (uint256 userDSCMintedAfter, ) = controller.getUserData(user);
        assertEq(dscToken.balanceOf(user), userDSCBeforeBalance - burnAmount);
        assertEq(userDSCMintedAfter, userDSCMintedBefore - burnAmount);
        // check that the amount was burned
        assertEq(
            dscToken.totalSupply(),
            dscTokenTotalSupplyBefore - burnAmount
        );
    }

    // ************************** //
    //    burnAndWithdraw test    //
    // ************************** //

    function testRevertIfBurnAndWithdrawBreaksHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        uint256 dscBurnAmount = mintAmount / 4;
        uint256 withdrawAmount = (wethDepositAmount * 90) / 100;
        uint256 collateralValue = controller.getUSDAmount(
            weth,
            wethDepositAmount - withdrawAmount
        );
        uint256 remainingMintedAmount = mintAmount - dscBurnAmount;
        uint256 expectedHealthFactor = (collateralValue * 1e18) /
            (remainingMintedAmount);
        dscToken.approve(address(controller), dscBurnAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCController.BelowMinHealthFactor.selector,
                expectedHealthFactor
            )
        );
        controller.burnAndWithdraw(weth, withdrawAmount, dscBurnAmount);
    }

    function testCanBurnAndWithdrawWhenNotBreakingHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        uint256 dscBurnAmount = mintAmount / 2;
        uint256 withdrawAmount = wethDepositAmount / 2;
        dscToken.approve(address(controller), dscBurnAmount);
        controller.burnAndWithdraw(weth, withdrawAmount, dscBurnAmount);

        (uint256 userMintedDSC, ) = controller.getUserData(user);
        uint256 expectedCollateralAmount = wethDepositAmount / 2;
        uint256 actualCollateralAmount = controller.getUserCollateralAmount(
            user,
            weth
        );
        assertEq(actualCollateralAmount, expectedCollateralAmount);
        assertEq(userMintedDSC, mintAmount - dscBurnAmount);
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
                DSCController.InvalidLiquidation.selector,
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
        uint256 dscAmountToLiquidate = controller.getUSDAmount(
            weth,
            userCollateralAmount + 0.1e18
        );
        vm.expectRevert(DSCController.InsufficientCollateralBalance.selector);
        controller.liquidate(user, weth, dscAmountToLiquidate);
    }

    function testCanLiquidateUnhealthyUser()
        public
        depositAndMintCollateral(weth)
    {
        address liquidator = address(2);
        vm.startPrank(liquidator);

        // Mint DSC token to liquidator in order to repay user debt
        ERC20Mock(wbtc).mint(liquidator, 10e8);
        ERC20Mock(wbtc).approve(address(controller), 10e8);
        controller.depositAndMint(wbtc, 10e8, mintAmount);
        controller.mintDSC(mintAmount);
        dscToken.approve(address(controller), mintAmount);

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
        uint256 dscAmountToLiquidate = mintAmount;
        uint256 collateralLiquidateAmount = controller.getTokenAmountFromUSD(
            weth,
            dscAmountToLiquidate
        );

        // Liquidate user
        controller.liquidate(user, weth, dscAmountToLiquidate);

        // Check health factor is above minimum
        userHealthFactor = controller.healthFactor(user);
        assert(userHealthFactor > controller.MIN_HEALTH_FACTOR());
        (uint256 mintedDSC, ) = controller.getUserData(user);
        uint256 userCollateralAmountAfter = controller.getUserCollateralAmount(
            user,
            weth
        );
        assertEq(mintedDSC, 0);
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
            address(dscToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.FlashOpsIsPaused.selector);
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
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
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfZeroFlashloanAmount() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(dscToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.InvalidFlashOp.selector);
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
            0,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfNotDSCTokenInFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(dscToken),
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
            address(dscToken),
            weth,
            wbtc
        );
        address randomERC20 = address(new ERC20Mock());
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCController.NotAllowedCollateral.selector,
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
            address(dscToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert();
        // receiver contract will not have enough DSC token to pay fee
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testRevertIfFlashLoanCallbackReturnFalse() public {
        BadFlashloanReceiverMock badReceiver = new BadFlashloanReceiverMock(
            address(controller),
            address(dscToken),
            weth,
            wbtc
        );
        vm.startPrank(user);
        vm.expectRevert(FlashOperations.FlashOpsFailed.selector);
        // receiver contract will not have enough DSC token to pay fee
        controller.executeFlashOperation(
            badReceiver,
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testShouldAllowUserToFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(dscToken),
            weth,
            wbtc
        );

        // mint receiver contract some DSC tokens
        vm.startPrank(address(controller));
        dscToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();
    }

    function testDSCTokenSupplyMustNotChangeOnFlashMint() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(dscToken),
            weth,
            wbtc
        );

        // mint receiver contract some DSC tokens
        vm.startPrank(address(controller));
        dscToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        uint256 beforeDSCSupply = dscToken.totalSupply();

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();

        uint256 afterDSCSupply = dscToken.totalSupply();
        assertEq(afterDSCSupply, beforeDSCSupply);
    }

    function testShouldSendExactFlashMintFeeAmount() public {
        receiver = new FlashloanReceiverMock(
            address(controller),
            address(dscToken),
            weth,
            wbtc
        );

        // mint receiver contract some DSC tokens
        vm.startPrank(address(controller));
        dscToken.mint(address(receiver), 1 ether);
        vm.stopPrank();

        uint256 flashFeeBPS = controller.flashOpsFeeBPS();
        uint256 expectedFeeAmount = (flashAmount * flashFeeBPS) / 1e18;
        uint256 beforeRecipientBalance = dscToken.balanceOf(feeRecipient);

        vm.startPrank(user);
        controller.executeFlashOperation(
            receiver,
            address(dscToken),
            flashAmount,
            "",
            FlashOperations.FlashOperationType.MINT
        );
        vm.stopPrank();

        uint256 afterRecipientBalance = dscToken.balanceOf(feeRecipient);
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
            address(dscToken),
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
            address(dscToken),
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
            address(dscToken),
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
            address(dscToken),
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
            address(dscToken),
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
        (uint256 userDSCMinted, ) = controller.getUserData(user);
        uint256 healthFactor = controller.healthFactor(user);
        assertEq(userDSCMinted, 0);
        assertEq(healthFactor, type(uint256).max);
    }

    function testCalculateCorrectHealthFactor()
        public
        depositAndMintCollateral(weth)
    {
        (uint256 userDSCMinted, uint256 collateralUsdValue) = controller
            .getUserData(user);
        uint256 expectedUserHF = (collateralUsdValue * 1e18) / userDSCMinted;
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
