// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "ds-test/test.sol";
import "../Hevm.sol";

import "../TokenLockStakeable.sol";
import "../TreehouseToken.sol";
import "../MultiSigs.sol";

uint256 constant ONE_DAY = 86400;

uint256 constant ONE_TOKEN = 10**18;

uint256 constant FIRST_UNLOCK = 1648746000; 

uint256 constant UNLOCK_END = FIRST_UNLOCK + ONE_DAY * 120;

contract User {
    TokenLockStakeable locker;

    constructor() {}

    receive() external payable {}

    function claim(address _locker) public {
        locker = TokenLockStakeable(_locker);
        locker.claim();
    }

    function claimReward(address _locker) public {

        locker = TokenLockStakeable(_locker);
        locker.claimReward();

    }
}


contract TokenLockStakeableTest is DSTest, Hevm {
    MultiSigs sigs;
    TreehouseToken treehouseToken;
    TokenLockStakeable locker;

    User user1;
    User user2;
    User user3;

    function setUp() public {
        treehouseToken = new TreehouseToken("Treehouse", "THF");

        uint256[] memory _unlockTimestamps = new uint256[](5);
        uint256[] memory _unlockPercentages = new uint256[](5);

        _unlockTimestamps[0] = 1648746000;
        _unlockTimestamps[1] = 1648746000 + ONE_DAY * 30;
        _unlockTimestamps[2] = 1648746000 + ONE_DAY * 60;
        _unlockTimestamps[3] = 1648746000 + ONE_DAY * 90;
        _unlockTimestamps[4] = 1648746000 + ONE_DAY * 120;

        _unlockPercentages[0] = 10;
        _unlockPercentages[1] = 10;
        _unlockPercentages[2] = 20;
        _unlockPercentages[3] = 20;
        _unlockPercentages[4] = 40;

        locker = new TokenLockStakeable(
            address(treehouseToken),
            UNLOCK_END,
            _unlockTimestamps,
            _unlockPercentages
        );

        user1 = new User();
        user2 = new User();
        user3 = new User();

        address[] memory users = new address[](3);
        uint256[] memory lockedAmounts = new uint256[](3);
        uint256[] memory rewards = new uint256[](3);

        lockedAmounts[0] = 200 * ONE_TOKEN;
        lockedAmounts[1] = 300 * ONE_TOKEN;
        lockedAmounts[2] = 500 * ONE_TOKEN;

        users[0] = address(user1);
        users[1] = address(user2);
        users[2] = address(user3);

        rewards[0] = 20 * ONE_TOKEN;
        rewards[1] = 30 * ONE_TOKEN;
        rewards[2] = 50 * ONE_TOKEN;

        treehouseToken.addAdmin(address(locker));
        treehouseToken.addAdmin(address(this));

        // mint tokens to  this contract in token contract
        treehouseToken.mint(1000 * ONE_TOKEN);

        treehouseToken.approve(address(locker), 1000 * ONE_TOKEN);

        assertEq(treehouseToken.balanceOf(address(this)), 1000 * ONE_TOKEN);

        // lock tokens to user1, user2 and user3 100, 200 and 300 tokens respectively
        locker.lock(users, lockedAmounts, rewards);

        assertEq(locker.lockedAmounts(address(user1)), 200 * ONE_TOKEN);
        assertEq(locker.lockedAmounts(address(user2)), 300 * ONE_TOKEN);
        assertEq(locker.lockedAmounts(address(user3)), 500 * ONE_TOKEN);

        assertEq(locker.claimedAmounts(address(user1)), 0);
        assertEq(locker.claimedAmounts(address(user2)), 0);
        assertEq(locker.claimedAmounts(address(user3)), 0);

        assertEq(locker.pendingRewards(address(user1)), 20 * ONE_TOKEN);
        assertEq(locker.pendingRewards(address(user2)), 30 * ONE_TOKEN);
        assertEq(locker.pendingRewards(address(user3)), 50 * ONE_TOKEN);

    }   

    function test_changePartnerAddress() public {

        // time travel to before the first unlock
        hevm.warp(FIRST_UNLOCK - 100);
        User newUser = new User();

        uint256 locked = locker.lockedAmounts(address(user1));
        uint256 reward = locker.pendingRewards(address(user1));

        locker.changePartnerAddress(address(user1), address(newUser));

        assertEq(locker.lockedAmounts(address(user1)), 0);
        assertEq(locker.claimedAmounts(address(user1)), 0);
        assertEq(locker.pendingRewards(address(user1)), 0);

        assertEq(locker.lockedAmounts(address(newUser)), locked);
        assertEq(locker.pendingRewards(address(newUser)), reward);

        assertEq(locker.currentUnlockRate(), 0);

    }

    function testFail_changePartnerAddress() public {

        // time travel to after the first unlock
        hevm.warp(FIRST_UNLOCK + 1);
        User newUser = new User();
        locker.changePartnerAddress(address(user1), address(newUser));

    }

    function test_claim() public {
        // travel after the first unlock timestamp, 
        // unlockrate should be 10
        hevm.warp(FIRST_UNLOCK + 1);

        assertEq(locker.currentUnlockRate(), 0);

        // user1 claim should get 10% of his locked tokens
        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 10);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN);

        // travel to a the point before the second unlock timestamp
        hevm.warp(FIRST_UNLOCK + 10000);

        // users claim now should get nothing
        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 10);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN);


        // travel to the point after the second unlock timestamp

        hevm.warp(FIRST_UNLOCK + ONE_DAY * 35);

        // users claim now should get another 10 percents of their locked tokens

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 20);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 2);


        // travel to after the third unlock
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 89);
        // users claim now should get another 10 percents of their locked tokens

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 40);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 4);


        // travel to after the fourth unlock
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 100);
        // users claim now should get another 10 percents of their locked tokens

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 60);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 6);


        // travel to after the fourth unlock
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 131);
        // users claim now should get another 10 percents of their locked tokens

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 100);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 10);

    }


    // All users claim one time after 1 year of locking token
    function test_claim2() public {

        hevm.warp(FIRST_UNLOCK + ONE_DAY * 365);

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 100);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 10);


        user1.claimReward(address(locker));
        user2.claimReward(address(locker));
        user3.claimReward(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 11);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 11);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 11);

    }

    function test_claim3() public {
        hevm.warp(FIRST_UNLOCK - 1);
        locker.updateCurrentUnlockRate();
        assertEq(locker.currentUnlockRate(), 0);

        hevm.warp(FIRST_UNLOCK + ONE_DAY * 70);

        
        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 40);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 4);
    }


    // fail if claim reward before the unlock end
    function testFail_claimReward() public {
        hevm.warp(FIRST_UNLOCK + 110 * ONE_DAY);
        user1.claimReward(address(locker));

    }


    // fail if set reward after the first unlock
    function testFail_setReward() public {

        hevm.warp(FIRST_UNLOCK + 120 * ONE_DAY + 1);
        locker.updateCurrentUnlockRate();
        // assertEq(locker.currentUnlockRate(), 100 );

        locker.setReward(address(user1), 1 * ONE_TOKEN);
    }

    // test success if set reward before any token unlocked
    function test_setReward(uint256 _reward) public {

        hevm.warp(FIRST_UNLOCK - 1);
        locker.updateCurrentUnlockRate();
        assertEq(locker.currentUnlockRate(), 0);
        locker.setReward(address(user1), _reward);
        assertEq(locker.pendingRewards(address(user1)), _reward);
    }

    function testFail_claimWhenPaused() public {
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 31);
        locker.pause();

        user1.claim(address(locker));
    }

    function testFail_claimRewardWhenPaused() public {
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 130);
        locker.pause();

        user1.claim(address(locker));

    }

    function test_pauseThenUnpause() public {
        
        hevm.warp(FIRST_UNLOCK + ONE_DAY * 30);
        locker.pause();


        hevm.warp(FIRST_UNLOCK + ONE_DAY * 91);

        locker.unpause();

        user1.claim(address(locker));

        assertEq(locker.currentUnlockRate(), 60);

        user2.claim(address(locker));
        user3.claim(address(locker));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 6);
    }

    function invariantCurrentUnlockRate() public {
        assertTrue(100 - locker.currentUnlockRate() >= 0);
    }
    function test_claimableBalance() public {
        // travel to the startTime
        hevm.warp(1648746000 - 1);

        // currentUnlockRate should be 0 and no reward
        uint256 claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 0);

        // travel after the startTime
        hevm.warp(1648746000 + 1);
        claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN);

        // travel to after the second unlock
        hevm.warp(1648746000 + ONE_DAY*30 + 1);
        claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 2);

        hevm.warp(1648746000 + ONE_DAY*60 + 1);
        claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 4);

        hevm.warp(1648746000 + ONE_DAY*90 + 1);
        claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 6);

        hevm.warp(1648746000 + ONE_DAY*122 + 1);
        claimable = locker.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 10);

    }

    function test_claimableBalance2() public {
        hevm.warp(1648746000 + ONE_DAY * 1000);
        uint256 claimable = locker.claimableBalance(address(user2));
        assertEq(claimable, 300 * ONE_TOKEN);
    }
}
