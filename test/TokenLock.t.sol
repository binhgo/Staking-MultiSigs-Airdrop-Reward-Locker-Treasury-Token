// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;
import "ds-test/test.sol";
import "../TokenLock.sol";
import "../TreehouseToken.sol";
import "../Hevm.sol";

uint256 constant ONE_DAY = 86400;

uint256 constant ONE_TOKEN = 10**18;

contract User {
    TokenLock tokenLock;

    constructor() {}

    receive() external payable {}

    function claim(address _tokenLock) public {
        tokenLock = TokenLock(_tokenLock);
        tokenLock.claim();
    }
}

contract TokenLockTest is DSTest, Hevm {
    TreehouseToken treehouseToken;
    TokenLock tokenLock;
    User user1;
    User user2;
    User user3;

    // deploy contracts, mint tokens in TreehouseToken,
    // lock tokens in tokenLock contract for 3 users.
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

        tokenLock = new TokenLock(
            address(treehouseToken),
            _unlockTimestamps,
            _unlockPercentages
        );

        user1 = new User();
        user2 = new User();
        user3 = new User();

        address[] memory users = new address[](3);
        uint256[] memory lockedAmounts = new uint256[](3);
        lockedAmounts[0] = 200 * ONE_TOKEN;
        lockedAmounts[1] = 300 * ONE_TOKEN;
        lockedAmounts[2] = 500 * ONE_TOKEN;

        users[0] = address(user1);
        users[1] = address(user2);
        users[2] = address(user3);

        treehouseToken.addAdmin(address(this));

        // mint tokens to  this contract in token contract
        treehouseToken.mint(1000 * ONE_TOKEN);

        treehouseToken.approve(address(tokenLock), 1000 * ONE_TOKEN);

        assertEq(treehouseToken.balanceOf(address(this)), 1000 * ONE_TOKEN);

        
        // lock tokens to user1, user2 and user3 100, 200 and 300 tokens respectively
        tokenLock.lock(users, lockedAmounts);

        assertEq(tokenLock.lockedAmounts(address(user1)), 200 * ONE_TOKEN);
        assertEq(tokenLock.lockedAmounts(address(user2)), 300 * ONE_TOKEN);
        assertEq(tokenLock.lockedAmounts(address(user3)), 500 * ONE_TOKEN);

        assertEq(treehouseToken.balanceOf(address(tokenLock)), 1000 * ONE_TOKEN);
    }

    function test_claim() public {
        // 1. travel to before the first unlock
        // expect to receive nothing

        hevm.warp(1648746000 - 100);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 0);
        assertEq(treehouseToken.balanceOf(address(user2)), 0);
        assertEq(treehouseToken.balanceOf(address(user3)), 0);

        // 2. travel to after the first unlock, expect to receive
        // some tokens. then claim.

        hevm.warp(1648746000 + 100);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN);

        // 3. travel to the third unlock, expect to receive the right amount
        // of token. Then claim, and continue until the last unlock.
        hevm.warp(1648746000 + ONE_DAY * 31);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 2);

        hevm.warp(1648746000 + ONE_DAY * 59);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 2);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 2);

        hevm.warp(1648746000 + ONE_DAY * 61);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 4);

        hevm.warp(1648746000 + ONE_DAY * 67);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 4);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 4);

        hevm.warp(1648746000 + ONE_DAY * 91);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 6);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 6);

        hevm.warp(1648746000 + ONE_DAY * 150);
        user1.claim(address(tokenLock));
        user2.claim(address(tokenLock));
        user3.claim(address(tokenLock));

        assertEq(treehouseToken.balanceOf(address(user1)), 20 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user2)), 30 * ONE_TOKEN * 10);
        assertEq(treehouseToken.balanceOf(address(user3)), 50 * ONE_TOKEN * 10);
    }

    function invariantCurrentUnlockRate() public {
        assertTrue(100 - tokenLock.currentUnlockRate() >= 0);
    }

    function testUnlockRateLen() public {
        assertEq(tokenLock.unlockRatesLength(), 5);
    }

    function test_claimableBalance() public {
        // travel to the startTime
        hevm.warp(1648746000 - 1);

        // currentUnlockRate should be 0 and no reward
        uint256 claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 0);

        // travel after the startTime
        hevm.warp(1648746000 + 1);
        claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN);

        // travel to after the second unlock
        hevm.warp(1648746000 + ONE_DAY*30 + 1);
        claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 2);

        hevm.warp(1648746000 + ONE_DAY*60 + 1);
        claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 4);

        hevm.warp(1648746000 + ONE_DAY*90 + 1);
        claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 6);

        hevm.warp(1648746000 + ONE_DAY*122 + 1);
        claimable = tokenLock.claimableBalance(address(user1));
        assertEq(claimable, 20 * ONE_TOKEN * 10);

    }

    function test_claimableBalance2() public {
        hevm.warp(1648746000 + ONE_DAY * 1000);
        uint256 claimable = tokenLock.claimableBalance(address(user2));
        assertEq(claimable, 300 * ONE_TOKEN);
    }
}
