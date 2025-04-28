// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../Hevm.sol";
import "ds-test/test.sol";

import "../Staking.sol";
import "../RewardManager.sol";
import "../TreehouseToken.sol";
import "../Treasury.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

uint256 constant PENALTY_RATE = 50;
uint256 constant START_TIME = 1648746000; // Appril 1 2022

uint256 constant ONE_DAY = 86400;
uint256 constant TOKEN = 10**18;

contract User {
    RewardManager manager;

    constructor(address _manager) {
        manager = RewardManager(_manager);
    }

    function callWithdrawUnlocked() public {
        manager.withdrawUnlocked();
    }

    function callWithdrawAll() public {
        manager.withdrawAll();
    }
}

contract RewardManagerTest is DSTest, Hevm{
    TreehouseToken treehouseToken;
    Treasury treasury;
    RewardManager manager;

    User user1;
    User user2;
    User user3;

    function setUp() public {
        hevm.warp(START_TIME);
        treehouseToken = new TreehouseToken("Treehouse", "THF");
        treasury = new Treasury("Treasury");

        manager = new RewardManager(
            address(treehouseToken),
            address(treasury),
            PENALTY_RATE
        );

        manager.addMinter(address(this));

        treehouseToken.addAdmin(address(manager));

        treehouseToken.addAdmin(address(this));

        user1 = new User(address(manager));
        user2 = new User(address(manager));
        user3 = new User(address(manager));

        manager.mint(address(user1), 100 * TOKEN, true);
        manager.mint(address(user2), 200 * TOKEN, true);
        manager.mint(address(user3), 300 * TOKEN, false);
    }

    // test the mint function
    function test_mint() public {
        (uint256 user1Total, uint256 user1Unlocked) = manager.balances(
            address(user1)
        );

        (uint256 user2Total, uint256 user2Unlocked) = manager.balances(
            address(user2)
        );
        (uint256 user3Total, uint256 user3Unlocked) = manager.balances(
            address(user3)
        );

        assertEq(user1Total, 100 * TOKEN);
        assertEq(user2Total, 200 * TOKEN);
        assertEq(user3Total, 300 * TOKEN);

        assertEq(user1Unlocked, 0);
        assertEq(user2Unlocked, 0);

        // user3 does not have withPenalty flag, so his tokens are all unlocked
        assertEq(user3Unlocked, 300 * TOKEN);

        // if mint right now, the locks index of user should be 0
        (uint256 user1Amount, uint256 user1UnlockTime) = manager.locks(
            address(user1),
            0
        );
        (uint256 user2Amount, uint256 user2UnlockTime) = manager.locks(
            address(user2),
            0
        );
        (uint256 user3Amount, uint256 user3UnlockTime) = manager.locks(
            address(user3),
            0
        );

        assertEq(user1Amount, 100 * TOKEN);
        assertEq(user2Amount, 200 * TOKEN);
        assertEq(user3Amount, 0);

        uint256 expectedUnlockTime = (block.timestamp / manager.ONE_WEEK()) *
            manager.ONE_WEEK() +
            manager.lockDuration();

        assertEq(user1UnlockTime, expectedUnlockTime);
        assertEq(user2UnlockTime, expectedUnlockTime);
        assertEq(user3UnlockTime, 0);

        assertEq(manager.lockedSupply(), 300 * TOKEN);
        assertEq(manager.totalSupply(), 600 * TOKEN);
    }

    // test withdrawUnlock before the tokens are unlocked
    function testFail_withdrawUnlocked() public {
        // if(timeTravel > manager.lockDuration()) revert("");

        hevm.warp(START_TIME + 56 * ONE_DAY);

        user1.callWithdrawUnlocked();
        user2.callWithdrawUnlocked();
        // user3.callWithdrawUnlocked();

        // assertEq(treehouseToken.balanceOf(address(user1)), 0);
        // assertEq(treehouseToken.balanceOf(address(user2)), 0);
        // assertEq(treehouseToken.balanceOf(address(user3)), 300 * TOKEN);
    }

    // test withdrawUnlock after the tokens was unlocked
    function test_withdrawUnlock2() public {
        hevm.warp(START_TIME + manager.lockDuration() + 1);

        user1.callWithdrawUnlocked();
        user2.callWithdrawUnlocked();
        user3.callWithdrawUnlocked();

        assertEq(treehouseToken.balanceOf(address(user1)), 100 * TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 200 * TOKEN);
        assertEq(treehouseToken.balanceOf(address(user3)), 300 * TOKEN);
    }

    function test_withdrawUnlock(uint256 timeTravel) public {
        if (timeTravel > START_TIME) return;
        hevm.warp(START_TIME + timeTravel);
        user3.callWithdrawUnlocked();
        assertEq(treehouseToken.balanceOf(address(user3)), 300 * TOKEN);
    }

    // function test_withdrawALl(uint256 timeTravel) public {
    //     hevm.warp(START_TIME + timeTravel);

    // }

    function test_withdrawAll() public {
        hevm.warp(START_TIME + 45 * ONE_DAY);

        manager.mint(address(user1), 100 * TOKEN, true);
        manager.mint(address(user2), 200 * TOKEN, true);
        // uint256 nextUnlockTime = (block.timestamp / manager.ONE_WEEK()) * manager.ONE_WEEK() + manager.lockDuration();

        hevm.warp(START_TIME + 90 * ONE_DAY + 1);

        // if call withdrawAll now, there is no penalty for the first lock and 50% penalty for the
        // second lock

        user1.callWithdrawAll();
        user2.callWithdrawAll();
        user3.callWithdrawAll();

        assertEq(treehouseToken.balanceOf(address(user1)), 150 * TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 300 * TOKEN);

        // treasury should receive the penalty amount of user1 and user2
        assertEq(treehouseToken.balanceOf(address(treasury)), 150 * TOKEN);

        // user3 should has no penalty
        assertEq(treehouseToken.balanceOf(address(user3)), 300 * TOKEN);
    }

    function test_withdrawableBalance() public {
        hevm.warp(START_TIME + 45 * ONE_DAY);

        manager.mint(address(user1), 100 * TOKEN, true);
        manager.mint(address(user2), 200 * TOKEN, true);
        // uint256 nextUnlockTime = (block.timestamp / manager.ONE_WEEK()) * manager.ONE_WEEK() + manager.lockDuration();

        hevm.warp(START_TIME + 90 * ONE_DAY + 1);

        (uint256 user1TotalAmount, uint256 user1PenalizedAmount) = manager
            .withdrawableBalance(address(user1));
        (uint256 user2TotalAmount, uint256 user2PenalizedAmount) = manager
            .withdrawableBalance(address(user2));

        assertEq(user1TotalAmount, 150 * TOKEN);
        assertEq(user2TotalAmount, 300 * TOKEN);

        assertEq(user1PenalizedAmount, 50 * TOKEN);
        assertEq(user2PenalizedAmount, 100 * TOKEN);
    }

    function test_pause() public {
        manager.pause();
        assertTrue(manager.paused());
    }

    function testFail_mintWhenPause() public {
        manager.pause();

        manager.mint(address(user1), 100 ether, true);
    }

    function testFail_withdrawUnlockedWhenPaused1() public {
        manager.pause();

        user1.callWithdrawUnlocked();
    }

    function testFail_withdrawAllWhenPaused1() public {
        manager.pause();
        user2.callWithdrawAll();
    }

    function test_pause1() public {
        manager.pause();
        assertTrue(manager.paused());

        manager.unpause();
        assertTrue(!manager.paused());
    }

    function test_mintWhenPause1() public {
        manager.pause();
        hevm.warp(block.timestamp + 10000);
        manager.unpause();
        manager.mint(address(user1), 100 ether, true);
    }

    function test_withdrawUnlockedWhenPaused() public {
        manager.pause();
        hevm.warp(block.timestamp + ONE_DAY * 90 + 1);
        manager.unpause();
        user1.callWithdrawUnlocked();
    }

    function test_withdrawAllWhenPaused() public {
        manager.pause();

        hevm.warp(block.timestamp + 10000);
        manager.unpause();
        user2.callWithdrawAll();
    }
}
