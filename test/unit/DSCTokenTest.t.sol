// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {PUSD} from "../../src/PUSD.sol";

contract PUSDTest is Test {
    PUSD pUSDToken;

    address public user = address(1);

    function setUp() external {
        pUSDToken = new PUSD();
    }

    function testMintToZeroAddress() public {
        vm.prank(pUSDToken.owner());
        vm.expectRevert(PUSD.InvalidMint.selector);
        pUSDToken.mint(address(0), 1000);
    }

    function testMintZeroAmount() public {
        vm.prank(pUSDToken.owner());
        vm.expectRevert(PUSD.InvalidMint.selector);
        pUSDToken.mint(address(this), 0);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert();
        pUSDToken.mint(address(this), 1000);
    }

    function testMintCorrectAmount() public {
        vm.prank(pUSDToken.owner());
        pUSDToken.mint(address(this), 1000);
        assertEq(pUSDToken.balanceOf(address(this)), 1000);
    }

    function testBurnZeroAmount() public {
        vm.prank(pUSDToken.owner());
        vm.expectRevert(PUSD.InvalidBurnAmount.selector);
        pUSDToken.burn(0);
    }

    function testBurnMoreThanBalance() public {
        vm.prank(pUSDToken.owner());
        vm.expectRevert(PUSD.AmountExceedsBalance.selector);
        pUSDToken.burn(1000);
    }

    function testBurnAmount() public {
        address owner = pUSDToken.owner();
        vm.prank(owner);
        pUSDToken.mint(owner, 1000);
        assertEq(pUSDToken.balanceOf(owner), 1000);
        pUSDToken.burn(1000);
        assertEq(pUSDToken.balanceOf(owner), 0);
    }
}
