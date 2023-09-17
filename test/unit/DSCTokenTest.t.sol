// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DSCToken} from "../../src/DSCToken.sol";

contract DSCTokenTest is Test {
    DSCToken dscToken;

    address public user = address(1);

    function setUp() external {
        dscToken = new DSCToken();
    }

    function testMintToZeroAddress() public {
        vm.prank(dscToken.owner());
        vm.expectRevert(DSCToken.InvalidMint.selector);
        dscToken.mint(address(0), 1000);
    }

    function testMintZeroAmount() public {
        vm.prank(dscToken.owner());
        vm.expectRevert(DSCToken.InvalidMint.selector);
        dscToken.mint(address(this), 0);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(user);
        vm.expectRevert();
        dscToken.mint(address(this), 1000);
    }

    function testMintCorrectAmount() public {
        vm.prank(dscToken.owner());
        dscToken.mint(address(this), 1000);
        assertEq(dscToken.balanceOf(address(this)), 1000);
    }

    function testBurnZeroAmount() public {
        vm.prank(dscToken.owner());
        vm.expectRevert(DSCToken.InvalidBurnAmount.selector);
        dscToken.burn(0);
    }

    function testBurnMoreThanBalance() public {
        vm.prank(dscToken.owner());
        vm.expectRevert(DSCToken.AmountExceedsBalance.selector);
        dscToken.burn(1000);
    }

    function testBurnAmount() public {
        address owner = dscToken.owner();
        vm.prank(owner);
        dscToken.mint(owner, 1000);
        assertEq(dscToken.balanceOf(owner), 1000);
        dscToken.burn(1000);
        assertEq(dscToken.balanceOf(owner), 0);
    }
}
