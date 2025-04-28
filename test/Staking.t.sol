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
    Staking staking;
    TreehouseToken treehouseToken;

    function callSet(
        address _staking,
        uint256 pid,
        uint256 allo
    ) public {
        staking = Staking(_staking);
        staking.set(pid, allo);
    }

    function callDeposit(
        address _staking,
        uint256 pid,
        uint256 amount
    ) public {
        staking = Staking(_staking);
        staking.deposit(pid, amount);
    }

    function callApprove(
        address _staking,
        address _token,
        uint256 amount
    ) public {
        treehouseToken = TreehouseToken(_token);
        treehouseToken.approve(_staking, amount);
    }

    function callWithdrawAndClaim(address _staking, uint256 _amount) public {
        staking = Staking(_staking);

        staking.withdrawAndClaim(0, _amount);
    }

    function callClaim(address _staking, uint256[] memory pids) public {
        staking = Staking(_staking);

        staking.claim(pids);
    }

    function callEmergencyWithdraw(address _staking, uint256 pid) public {
        staking = Staking(_staking);
        staking.emergencyWithdraw(pid);
    }

    function callTransfer(address token, address to, uint256 amount)  public {
        treehouseToken = TreehouseToken(token);
        treehouseToken.transfer(to, amount);
    }
}

contract StakingTest is DSTest, Hevm {
    Staking staking;
    RewardManager rewardManager;
    TreehouseToken treehouseToken;
    TreehouseToken LPToken;
    TreehouseToken rewardToken;
    Treasury treasury;

    User user1;
    User user2;
    User user3;

    function setUp() public {
        treehouseToken = new TreehouseToken("Treehouse", "THF");
        LPToken = new TreehouseToken("LP", "LP");
        rewardToken = new TreehouseToken("Treehouse", "THF");
        treasury = new Treasury("treasury");

        rewardManager = new RewardManager(
            address(rewardToken),
            address(treasury),
            PENALTY_RATE
        );

        uint128[] memory startTimeOffset = new uint128[](5);
        startTimeOffset[0] = 0;
        startTimeOffset[1] = 30 * uint128(ONE_DAY);
        startTimeOffset[2] = 60 * uint128(ONE_DAY);
        startTimeOffset[3] = 90 * uint128(ONE_DAY);
        startTimeOffset[4] = 120 * uint128(ONE_DAY);
        uint128[] memory rewardPerSecond = new uint128[](5);
        rewardPerSecond[0] = uint128(5 * TOKEN);
        rewardPerSecond[1] = uint128(4 * TOKEN);
        rewardPerSecond[2] = uint128(3 * TOKEN);
        rewardPerSecond[3] = uint128(2 * TOKEN);
        rewardPerSecond[4] = uint128(TOKEN);

        staking = new Staking(
            address(rewardManager),
            START_TIME,
            startTimeOffset,
            rewardPerSecond
        );

        staking.add(20, address(treehouseToken));
        staking.add(80, address(LPToken));

        user1 = new User();
        user2 = new User();
        user3 = new User();

        treehouseToken.addAdmin(address(this));

        treehouseToken.mintTo(address(user1), 100 * TOKEN);
        treehouseToken.mintTo(address(user2), 300 * TOKEN);
        treehouseToken.mintTo(address(user3), 500 * TOKEN);

        user1.callApprove(
            address(staking),
            address(treehouseToken),
            100 * TOKEN
        );
        user2.callApprove(
            address(staking),
            address(treehouseToken),
            300 * TOKEN
        );
        user3.callApprove(
            address(staking),
            address(treehouseToken),
            500 * TOKEN
        );

        // time travel to after the start time
        hevm.warp(staking.startTime() + 1);

        user1.callDeposit(address(staking), 0, 100 * TOKEN);
        user2.callDeposit(address(staking), 0, 300 * TOKEN);
        user3.callDeposit(address(staking), 0, 500 * TOKEN);

        rewardManager.addMinter(address(staking));

        rewardToken.addAdmin(address(rewardManager));
    }

    // test the add pool function: revert if the token already existed.
    function testFail_addPool() public {
        // add the first pool
        staking.add(20, address(treehouseToken));

        // add the second pool with the same token

        staking.add(80, address(treehouseToken));
    }

    // add pool fail if token address zero
    function testFail_addPool1() public {
        staking.add(20, address(0));
    }

    // test add pool success
    function test_addPools() public {
        assertEq(staking.totalAllocPoint(), 100);

        // assertEq(address(staking.poolInfo(0).stakingToken), address(treehouseToken));
        // assertEq(address(staking.poolInfo(1).stakingToken), address(LPToken));

        // assertEq(staking.poolInfo(0).allocPoint, 20);
        // assertEq(staking.poolInfo(1).allocPoint, 80);

        assertEq(staking.rewardTokenPerInterval(), 5 * TOKEN);
    }

    // fail if call set on a non-exist pool
    function testFail_set() public {
        staking.set(2, 100);
    }

    function testFail_callSetFromUser() public {
        User user = new User();
        user.callSet(address(staking), 0, 100);
    }

    function test_set() public {
        staking.set(0, 100);
        assertEq(staking.totalAllocPoint(), 180);
    }

    function test_updateRewardManager(address _rewardManager) public {
        if (_rewardManager == address(0)) return;
        staking.updateRewardManager(_rewardManager);
        assertEq(staking.rewardManager(), _rewardManager);
    }

    function test_deposit() public {
        assertEq(treehouseToken.balanceOf(address(staking)), 900 * TOKEN);

        (uint256 amount, uint256 rewardDebt) = staking.userInfo(
            0,
            address(user1)
        );

        assertEq(amount, 100 * TOKEN);

        hevm.warp(staking.startTime() + 20 * ONE_DAY);

        // if no one update pool then rewardDebt still zero
        assertEq(rewardDebt, 0);

        staking.massUpdatePools();

        (amount, rewardDebt) = staking.userInfo(0, address(user1));

        assertEq(amount, 100 * TOKEN);
        assertEq(rewardDebt, 0);
    }

    // test deposit the second times
    // expect to receive all reward before the new deposit
    // amount add up
    function test_deposit2() public {
        (
            IERC20 _stakingToken,
            uint256 _accRewardPerShare,
            uint256 _lastRewardBlock,
            uint256 _allocPoint,
            uint256 _tokenBalance
        ) = staking.poolInfo(0);

        assertEq(_accRewardPerShare, 0);

        hevm.warp(staking.startTime() + 20 * ONE_DAY);

        treehouseToken.mintTo(address(user1), 50 * TOKEN);

        user1.callApprove(
            address(staking),
            address(treehouseToken),
            50 * TOKEN
        );

        user1.callDeposit(address(staking), 0, 50 * TOKEN);

        (uint256 amount, uint256 rewardDebt) = staking.userInfo(
            0,
            address(user1)
        );

        assertEq(amount, 150 * TOKEN);

        assertEq(staking.rewardTokenPerInterval(), 5 * TOKEN);

        (
            IERC20 stakingToken,
            uint256 accRewardPerShare,
            uint256 lastRewardBlock,
            uint256 allocPoint,
            uint256 tokenBalance
        ) = staking.poolInfo(0);

        uint256 duration = 20 * ONE_DAY - 1;
        uint256 expectedAccReward = (duration *
            staking.rewardTokenPerInterval() *
            allocPoint) / staking.totalAllocPoint();
        expectedAccReward = ((expectedAccReward * 1e12) / (900 * TOKEN));

        assertEq(expectedAccReward, accRewardPerShare); //------------------------------ test fail accRewardPerShare ---------------------

        assertEq(address(stakingToken), address(treehouseToken));

        assertEq(lastRewardBlock, staking.startTime() + 20 * ONE_DAY);

        assertEq(lastRewardBlock, staking.startTime() + 20 * ONE_DAY);

        assertEq(allocPoint, 20);
    }

    function test_withdrawAndClaim(uint96 _amount) public {
        uint256 amount = uint256(_amount);
        (uint256 old_amount, uint256 rewardDebt) = staking.userInfo(
            0,
            address(user1)
        );

        if (amount > old_amount || amount == 0) {
            return;
        }

        assertEq(rewardDebt, 0);

        user1.callWithdrawAndClaim(address(staking), amount);

        (uint256 new_amount, uint256 new_rewardDebt) = staking.userInfo(
            0,
            address(user1)
        );
        (
            IERC20 stakingToken,
            uint256 accRewardPerShare,
            uint256 lastRewardBlock,
            uint256 allocPoint,
            uint256 tokenBalance
        ) = staking.poolInfo(0);

        assertEq(treehouseToken.balanceOf(address(user1)), amount);

        uint256 expectedRewardDebt = (old_amount * accRewardPerShare) / 1e12;

        assertEq(new_amount, old_amount - amount);

        assertEq(new_rewardDebt, expectedRewardDebt);
    }

    function testFail_claim() public {
        uint256[] memory pids = new uint256[](2);
        pids[0] = 0;
        pids[1] = 2;

        user1.callClaim(address(staking), pids);
    }

    function test_claim() public {
        uint256[] memory pids = new uint256[](1);
        pids[0] = 0;

        hevm.warp(START_TIME + 20 * ONE_DAY);

        user1.callClaim(address(staking), pids);
        user2.callClaim(address(staking), pids);
        user3.callClaim(address(staking), pids);

        uint256 duration = 20 * ONE_DAY - 1;
        uint256 user1ExpectedReward;
        uint256 user2ExpectedReward;
        uint256 user3ExpectedReward;

        uint256 rewardPerShare = (duration * 5 * TOKEN * 20 * 1e12) /
            (100 * 900 * TOKEN); // reward per share of pool 0

        user1ExpectedReward = (rewardPerShare * 100 * TOKEN) / 1e12;
        user2ExpectedReward = (rewardPerShare * 300 * TOKEN) / 1e12;
        user3ExpectedReward = (rewardPerShare * 500 * TOKEN) / 1e12;

        (uint256 total, uint256 unlocked) = rewardManager.balances(
            address(user1)
        );

        assertEq(total, user1ExpectedReward);
        assertEq(unlocked, 0);

        (total, unlocked) = rewardManager.balances(address(user2));
        assertEq(user2ExpectedReward, total);

        (total, unlocked) = rewardManager.balances(address(user3));
        assertEq(user3ExpectedReward, total);
    }

    function test_emergencyWithdraw() public {
        hevm.warp(START_TIME + 365 * ONE_DAY);

        user1.callEmergencyWithdraw(address(staking), 0);
        user2.callEmergencyWithdraw(address(staking), 0);
        user3.callEmergencyWithdraw(address(staking), 0);

        assertEq(treehouseToken.balanceOf(address(user1)), 100 * TOKEN);
        assertEq(treehouseToken.balanceOf(address(user2)), 300 * TOKEN);
        assertEq(treehouseToken.balanceOf(address(user3)), 500 * TOKEN);
    }

    // test when pause contract
    function testFail_depositWhenPaused() public {
        staking.pause();
        treehouseToken.mintTo(address(user1), 100 * TOKEN);
        user1.callApprove(
            address(staking),
            address(treehouseToken),
            100 * TOKEN
        );

        // expect to fail because the contract is paused
        user1.callDeposit(address(staking), 0, 100 * TOKEN);
    }

    function testFail_withdrawAndClaimWhenPaused() public {
        staking.pause();
        user1.callWithdrawAndClaim(address(staking), 100 * TOKEN);
    }

    function testFail_claimWhenPaused() public {
        staking.pause();
        uint256[] memory pid = new uint256[](1);
        pid[0] = 0;
        user1.callClaim(address(staking), pid);
    }

    // test when pause then unpause
    function test_depositWhenPaused1() public {
        staking.pause();
        treehouseToken.mintTo(address(user1), 100 * TOKEN);
        user1.callApprove(
            address(staking),
            address(treehouseToken),
            100 * TOKEN
        );
        hevm.warp(block.timestamp + 100000);
        staking.unpause();
        user1.callDeposit(address(staking), 0, 100 * TOKEN);
    }

    function test_withdrawAndClaimWhenPaused1() public {
        staking.pause();
        hevm.warp(block.timestamp + 100000);
        staking.unpause();
        user1.callWithdrawAndClaim(address(staking), 100 * TOKEN);
    }

    function test_claimWhenPaused1() public {
        staking.pause();
        uint256[] memory pid = new uint256[](1);
        pid[0] = 0;
        hevm.warp(block.timestamp + 100000);
        staking.unpause();
        user1.callClaim(address(staking), pid);
    }

    // test the pendingReward view function
    function test_pendingReward() public {
        hevm.warp(block.timestamp + 100000);

        // update emission and pools
        staking.updateEmissions();
        staking.massUpdatePools();

        (
            IERC20 stakingToken,
            uint256 accRewardPerShare,
            uint256 lastRewardBlock,
            uint256 allocPoint,
            uint256 tokenBalance
        ) = staking.poolInfo(0);

        (uint256 amount, uint256 rewardDebt) = staking.userInfo(
            0,
            address(user1)
        );

        uint256 duration = block.timestamp - lastRewardBlock;

        uint256 accummulatedReward = (accRewardPerShare * amount) / allocPoint;
    }

    function test_flushToken() public {
        treehouseToken.mintTo(address(user3), 500 * TOKEN);
        user3.callApprove(
            address(staking),
            address(treehouseToken),
            500 * TOKEN
        );

        user3.callTransfer(address(treehouseToken), address(this), 500 * TOKEN);

        staking.flushLostToken(0);
        assertEq(treehouseToken.balanceOf(address(this)), 500 * TOKEN);
    }
}
