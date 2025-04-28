// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "ds-test/test.sol";
import "../TreehouseToken.sol";
import "../Hevm.sol";

contract TreehouseTokenTest is DSTest, Hevm {
    TreehouseToken token;

    function setUp() public {
        token = new TreehouseToken("MyToken", "MTK");

        token.addAdmin(address(this));
        assertTrue(token.admins(address(this)));
    }

    function test_addAdmin(address newAdmin) public {
        if(newAdmin == address(0) || newAdmin == address(this)) return;
        token.addAdmin(newAdmin);
        assertTrue(token.admins(newAdmin));

    }

    function testFail_addOldAdmin() public {
        token.addAdmin(address(this));
    }

    function testFail_addAdminZero() public {
        token.addAdmin(address(0));
    }

    function test_approve() public {
        token.mint(100 ether);

        token.approve(0x49AB92A84912B285dCC5B49230f51ebDba4A1788, 10 ether);

        assertEq(token.allowance(address(this), 0x49AB92A84912B285dCC5B49230f51ebDba4A1788), 10 ether);
    }


    function test_decreaseAllowance() public {
        token.mint(100 ether);

        token.approve(0x49AB92A84912B285dCC5B49230f51ebDba4A1788, 10 ether);

        assertEq(token.allowance(address(this), 0x49AB92A84912B285dCC5B49230f51ebDba4A1788), 10 ether);

        token.decreaseAllowance(0x49AB92A84912B285dCC5B49230f51ebDba4A1788, 5 ether);

        assertEq(token.allowance(address(this), 0x49AB92A84912B285dCC5B49230f51ebDba4A1788), 5 ether);
    }

    function test_increaseAllowance() public {
        token.mint(100 ether);

        token.approve(0x49AB92A84912B285dCC5B49230f51ebDba4A1788, 10 ether);

        assertEq(token.allowance(address(this), 0x49AB92A84912B285dCC5B49230f51ebDba4A1788), 10 ether);

        token.increaseAllowance(0x49AB92A84912B285dCC5B49230f51ebDba4A1788, 5 ether);

        assertEq(token.allowance(address(this), 0x49AB92A84912B285dCC5B49230f51ebDba4A1788), 15 ether);
    }


    function test_removeAdmin() public {
        token.removeAdmin(address(this));
        assertTrue(!token.admins(address(this)));
    }

    function test_mint(uint96 amount) public {
        if (amount > token.maxSupply()) return;
        token.mint(uint256(amount));
        assertEq(token.balanceOf(address(this)), uint256(amount));
    }

    function test_mintTo(uint96 amount) public {
        if (amount > token.maxSupply()) return;
        token.mintTo(address(this), uint256(amount));
        assertEq(token.balanceOf(address(this)), uint256(amount));
    }

    function test_burn(uint96 amount) public {
        if (amount > token.maxSupply()) return;

        token.mint(uint256(amount));
        assertEq(token.balanceOf(address(this)), uint256(amount));

        assertEq(token.totalSupply(), uint256(amount));

        token.burn(uint256(amount));
        assertEq(token.balanceOf(address(this)), 0);

        assertEq(token.totalSupply(), 0);
    }

    function testFail_mintOverMaxSupply() public {
        token.mint(token.maxSupply() + 1);
    }

    function test_pause() public {
        token.pause();
        assertTrue(token.paused());
        token.unpause();
        assertTrue(!token.paused());
    }

    function testFail_mintWhenPaused() public {
        token.pause();

        token.mint(100);
    }

    function testFail_mintToWhenPaused() public {
        token.pause();
        token.mintTo(address(this), 100);
    }

    function test_setMaxSupply() public {
        hevm.warp(block.timestamp + token.TIME_INTERVAL() * 3 + 1 );

        token.setMaxSupply( (1_000_000_000 + 1_000_000_000 /100) * 10**18  );

        assertEq(token.maxSupply(), (1_000_000_000 + 1_000_000_000 /100) * 10**18 );
    }


    function testFail_setMaxSupply() public {

        hevm.warp(block.timestamp + token.TIME_INTERVAL() * 3 + 1 );

        token.setMaxSupply( (1_000_000_000 + 1_000_000_000 /100) * 10**18  + 1 );

        // assertEq(token.maxSupply(), (1_000_000_000 + 1_000_000_000 /100) * 10**18  + 1);

    }

    function invariant_decimal() public {
        assertEq(token.decimals(), 18);
    }
}
