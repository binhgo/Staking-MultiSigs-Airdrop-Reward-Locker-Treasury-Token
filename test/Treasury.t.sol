//SPDX-License-Identifier: MIT
pragma solidity ^ 0.8.9;

import "../Hevm.sol";
import "ds-test/test.sol";

import "../TreehouseToken.sol";
import "../Treasury.sol";

uint256 constant TOKEN = 10 ** 18;

contract Admin {
    Treasury treasury;

    constructor(address _treasury) {
        treasury = Treasury(payable(_treasury));
    }

    function callWithdrawToken(address _token, uint256 amount) public {
        treasury.withdrawToken(_token, amount);
    }

    function callWithdrawNative(uint256 amount) public {
        treasury.withdrawNative(amount);
    }

    receive() external payable {}
 }

contract TreasuryTest is DSTest, Hevm{

    Treasury treasury;
    TreehouseToken treehouseToken;

    Admin admin1;
    Admin admin2;
    Admin admin3;

    function setUp() public {
        treasury = new Treasury("Treasury");
        treehouseToken = new TreehouseToken("Treehouse", "THF");

        treehouseToken.addAdmin(address(this));
        treehouseToken.mintTo(address(treasury), 100 * TOKEN);

        admin1 = new Admin(address(treasury));
        admin2 = new Admin(address(treasury));
        admin3 = new Admin(address(treasury));

        (bool success, ) = address(treasury).call{value: 100 ether}("");
        require(success);

        treasury.addAdmin(address(admin1));
        treasury.addAdmin(address(admin2));
        treasury.addAdmin(address(admin3));

    }
    
    function test_balance() public {
        assertEq(address(treasury).balance, 100 ether);
    }

    function test_AddAdmin() public {
        assertTrue(treasury.admins(address(admin1)));
        assertTrue(treasury.admins(address(admin2)));
        assertTrue(treasury.admins(address(admin3)));
    } 

    function test_removeAdmin() public {
        treasury.removeAdmin(address(admin1));
        treasury.removeAdmin(address(admin2));
        treasury.removeAdmin(address(admin3));

        assertTrue(!treasury.admins(address(admin1)));
        assertTrue(!treasury.admins(address(admin2)));
        assertTrue(!treasury.admins(address(admin3)));        
    }

    function testFail_addAdmin() public {
        treasury.addAdmin(address(admin1));
    }

    function testFail_removeAdmin() public {
        treasury.removeAdmin(address(admin1));
        treasury.removeAdmin(address(admin1));
    }

    function test_withdrawToken() public {
        admin1.callWithdrawToken(address(treehouseToken), 100 * TOKEN);

        assertEq(treehouseToken.balanceOf(address(admin1)), 100 * TOKEN);
    }

    // test fail not admin
    function testFail_withdrawToken() public {

        Admin admin4 = new Admin(address(treasury));
        admin4.callWithdrawToken(address(treehouseToken), 100 * TOKEN);

    }

    // test fail not enough amount
    function testFail_withdrawToken1() public {
        admin2.callWithdrawToken(address(treehouseToken), 110 * TOKEN);
    }
    
    function test_withdrawNative() public {
        admin3.callWithdrawNative(100 * TOKEN);
        assertEq(address(admin3).balance, 100 ether);
        assertEq(address(treasury).balance, 0);
    }   

    // test fail not admin
    function testFail_withdrawNative() public {
        Admin admin4 = new Admin(address(treasury));
        admin4.callWithdrawNative(100 ether);
    }

    // test fail not enough amount
    function testFail_withdrawNative1() public {
        admin2.callWithdrawNative(120 * TOKEN);
    }

    function testFail_withdrawTokenWhenPause() public {
        treasury.pause();
        admin1.callWithdrawToken(address(treehouseToken), 100 * TOKEN);
    }

    function testFail_withdrawNativeWhenPause() public {
        treasury.pause();
        admin2.callWithdrawNative(100 * TOKEN);
    }

    // pause then unpause then withdraw
    function test_withdrawNative2() public {
        treasury.pause();

        hevm.warp(10000000);

        treasury.unpause();

        admin3.callWithdrawNative(100 * TOKEN);

        assertEq(address(admin3).balance, 100 * TOKEN);
    }

    // pause then unpause then withdraw
    function test_withdrawToken2() public {
        treasury.pause();

        hevm.warp(10000000);
        
        treasury.unpause();

        admin3.callWithdrawToken(address(treehouseToken), 100 * TOKEN);

        assertEq(treehouseToken.balanceOf(address(admin3)), 100 * TOKEN);
    }
}