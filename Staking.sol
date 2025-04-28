// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IRewardManager.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @notice This contract DOES NOT support Fee-On-Transfer Tokens
 */
contract Staking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Info of each user
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided
        uint256 rewardDebt; // Reward debt. Same as Sushiswap
    }

    // Info of each pool
    struct PoolInfo {
        IERC20 stakingToken; // Address of token
        uint256 accRewardPerShare; // Accumulated THF token per share, times 1e12
        uint256 lastRewardBlock; // Last block number that THF token distribution occurs
        uint256 allocPoint; // How many allocation points assigned to this pool
        uint256 tokenBalance; // Total balance of this pool
    }

    // Info of each emission schedule
    struct EmissionPoint {
        uint128 startTimeOffset; // start time offset this reward rate is applied
        uint128 rewardsPerSecond; // rate applied to this emission schedule
    }

    bool public paused;

    // Reward manager to manage claimed amount
    // when user claim, pending reward will be vested to Reward Manager and locked there
    // user can withdraw 100% reward after locked period. ex: 12 weeks
    // user can only withdraw 50% reward before locked period. 50% remain will go to Reward Reserve
    address public rewardManager;

    // THF token created per interval for reward
    uint256 public rewardTokenPerInterval;

    // Total allocation points. Must be the sum of all allocation points in all pools
    uint256 public totalAllocPoint;

    // staking start time
    uint256 public startTime;

    uint256 private constant ACC_PRECISION = 1e12;

    // pool -> address -> user info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Info of each pool
    PoolInfo[] public poolInfo;

    // Info of each emission schedule
    EmissionPoint[] public emissionSchedule;

    // events
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256[] indexed pids, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, uint256 allocPoint, address indexed lpToken);
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(uint256 indexed pid, uint256 lastRewardBlock, uint256 lpSupply, uint256 accRewardPerShare);
    event LogUpdateEmissionRate(address indexed user, uint256 rewardTokenPerInterval);

    event PauseContract(uint256 indexed timestamp);
    event UnpauseContract(uint256 indexed timestamp);
    event RewardManagerUpdated(address indexed rewardManager);
    event StartBlockUpdated(uint256 indexed startTime);
    event LostTokenFlushed(uint256 amount);

    /**
     * @dev The pause mechanism
     */
    modifier pausable() {
        require(!paused, "PAUSED");
        _;
    }

    /**
     * @dev Constructor
     * @param _rewardManager The address of reward manager contract
     * @param _startTime The timestamp at which staking will begin
     * @param _startTimeOffset Array of duration count from startTime when new staking rates will be applied.
     * @param _rewardsPerSecond Array of staking reward rates
     */
    constructor(
        address _rewardManager,
        uint256 _startTime,
        uint128[] memory _startTimeOffset,
        uint128[] memory _rewardsPerSecond
    ) {
        require(_rewardManager != address(0), "ADDRESS_0");
        require(_startTime > block.timestamp, "INVALID_START_TIME");

        rewardManager = _rewardManager;
        startTime = _startTime;

        require(_startTimeOffset.length == _rewardsPerSecond.length, "INVALID_SCHEDULE");

        // _startTimeOffset array must has increasing order
        for(uint256 i; i < _startTimeOffset.length - 1; i++ ) {
            require(_startTimeOffset[i+1] > _startTimeOffset[i], "INVALID_START_TIME_OFFSET");
        }

        unchecked {
            for (uint256 i = _startTimeOffset.length - 1; i + 1 != 0; i--) {
                emissionSchedule.push(
                    EmissionPoint({startTimeOffset : _startTimeOffset[i], rewardsPerSecond : _rewardsPerSecond[i]})
                );
            }
        }
    }

    /**
     * @dev Pause staking functions
     */
    function pause() external onlyOwner {
        paused = true;
        emit PauseContract(block.timestamp);
    }

    /**
     * @dev Unpause staking functions
     */
    function unpause() external onlyOwner {
        paused = false;
        emit UnpauseContract(block.timestamp);
    }

    function poolLength() external view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param allocPoint AP of the new pool.
    /// @param _stakingToken Address of the LP ERC-20 token.
    function add(uint256 allocPoint, address _stakingToken) external onlyOwner {

        require(_stakingToken != address(0), "ADDRESS_0");

        // check if the _stakingToken already in another pool
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; pid++) {
            require(address(poolInfo[pid].stakingToken) != _stakingToken, "TOKEN_ALREADY_EXISTS");
        }

        uint256 lastRewardBlock = block.timestamp > startTime ? block.timestamp : startTime;

        // 2.1.1 -> pre-calculating pool info before update totalAllocPoint
        _updateEmissions();
        this.massUpdatePools();
        totalAllocPoint += allocPoint;

        poolInfo.push(
            PoolInfo({
        stakingToken : IERC20(_stakingToken),
        allocPoint : allocPoint,
        lastRewardBlock : lastRewardBlock,
        accRewardPerShare : 0,
        tokenBalance : 0
        })
        );
        emit LogPoolAddition(poolInfo.length - 1, allocPoint, _stakingToken);
    }

    /// @notice Update the given pool's allocation point.
    /// @dev Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(
        uint256 _pid,
        uint256 _allocPoint
    ) external onlyOwner {

        require(_pid < poolInfo.length, "POOL_DOES_NOT_EXIST");

        this.massUpdatePools();

        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice Update RewardManager contract address.
    /// @param _rewardManager The address of the new RewardManager contract.
    function updateRewardManager(address _rewardManager) external onlyOwner {
        require(_rewardManager != address(0), "ADDRESS_ZERO");
        rewardManager = _rewardManager;
        emit RewardManagerUpdated(_rewardManager);
    }

    /// @notice View function to see pending  on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pending) {
        require(_pid < poolInfo.length, "POOL_DOES_NOT_EXIST");

        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        if (user.amount == 0) {
            return 0;
        }

        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 stakingSupply = pool.tokenBalance;

        if (block.timestamp > pool.lastRewardBlock && stakingSupply != 0) {
            uint256 duration = (block.timestamp - pool.lastRewardBlock);
            uint256 reward = (duration * rewardTokenPerInterval * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare = accRewardPerShare + ((reward * ACC_PRECISION) / stakingSupply);
        }

        if (accRewardPerShare == 0) {
            return 0;
        }

        pending = ((user.amount * accRewardPerShare) / ACC_PRECISION) - user.rewardDebt;
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            this.updatePool(pid);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) external returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardBlock) {
            uint256 stakingSupply = pool.tokenBalance;
            if (stakingSupply > 0) {
                uint256 duration = (block.timestamp - pool.lastRewardBlock);
                uint256 reward = (duration * rewardTokenPerInterval * pool.allocPoint) / totalAllocPoint;
                pool.accRewardPerShare = pool.accRewardPerShare + ((reward * ACC_PRECISION) / stakingSupply);
            }
            pool.lastRewardBlock = block.timestamp;
            poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, stakingSupply, pool.accRewardPerShare);
        }
    }

    /// @notice Deposit LP tokens for  allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    function deposit(
        uint256 pid,
        uint256 amount
    ) external nonReentrant pausable {
        require(amount > 0, "AMOUNT_ZERO");
        require(pid < poolInfo.length, "POOL_DOES_NOT_EXIST");

        _updateEmissions();
        PoolInfo memory pool = this.updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];

        // if user is having deposited amount in this pool
        // -> calculate pendingReward and send that amount to rewardManager
        // -> fresh calculation again with new amount
        if (user.amount > 0) {
            uint256 accumulatedReward = (user.amount * pool.accRewardPerShare) / ACC_PRECISION;
            uint256 _pendingReward = accumulatedReward - user.rewardDebt;

            uint256[] memory eventArray = new uint256[](1);
            eventArray[0] = pid;

            if (_pendingReward > 0) {
                bool success = IRewardManager(rewardManager).mint(msg.sender, _pendingReward, true);
                require(success, "TOKEN_MINT_FAILED");
                emit Claim(msg.sender, eventArray, _pendingReward);
            }
        }

        // transfer token from sender to this contract
        // 2.1.2 might cause re-entrance ERC 777 (token has callback hook) -> added nonReentrant modifier
        poolInfo[pid].stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        // increase user amount and re-calculate rewardDebt
        user.amount += amount;
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / ACC_PRECISION;

        // increase pool balance
        poolInfo[pid].tokenBalance += amount;

        emit Deposit(msg.sender, pid, amount);
    }

    /// @notice Withdraw LP tokens.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    function withdrawAndClaim(
        uint256 pid,
        uint256 amount
    ) external pausable {

        require(amount > 0, "INVALID_AMOUNT");

        require(pid < poolInfo.length, "POOL_DOES_NOT_EXIST");

        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amount, "NOT_ENOUGH_AMOUNT");

        _updateEmissions();
        PoolInfo memory pool = this.updatePool(pid);

        // calculate _pendingReward
        uint256 accumulatedReward = (user.amount * pool.accRewardPerShare) / ACC_PRECISION;
        uint256 _pendingReward = accumulatedReward - user.rewardDebt;

        // decrease user amount
        user.amount -= amount;
        // re-calculate rewardDebt
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / ACC_PRECISION;

        // decrease pool balance
        poolInfo[pid].tokenBalance -= amount;

        uint256[] memory eventArray = new uint256[](1);
        eventArray[0] = pid;

        // send _pendingReward amount to rewardManager
        if (_pendingReward > 0) {
            bool success = IRewardManager(rewardManager).mint(msg.sender, _pendingReward, true);
            require(success, "TOKEN_MINT_FAILED");
            emit Claim(msg.sender, eventArray, _pendingReward);
        }

        // transfer token to sender
        pool.stakingToken.safeTransfer(msg.sender, amount);

        emit Withdraw(msg.sender, pid, amount);
    }

    /// @notice Claim reward of multiple pools
    /// @param pids The index of the pool. See `poolInfo`.
    function claim(uint256[] calldata pids) external pausable {
        _updateEmissions();
        uint256 _pendingReward;

        // loop thru all pools and calculate _pendingReward and rewardDebt for each pool
        for (uint256 i = 0; i < pids.length; i++) {

            require(pids[i] < poolInfo.length, "POOL_DOES_NOT_EXIST");

            PoolInfo memory pool = this.updatePool(pids[i]);
            UserInfo storage user = userInfo[pids[i]][msg.sender];

            if (user.amount > 0 && pool.accRewardPerShare > 0) {
                uint256 accumulatedReward = (user.amount * pool.accRewardPerShare) / ACC_PRECISION;
                _pendingReward = _pendingReward + accumulatedReward - user.rewardDebt;

                // update user rewardDebt for this pool
                user.rewardDebt = accumulatedReward;
            }
        }

        // send _pendingReward amount to rewardManager
        if (_pendingReward > 0) {
            bool success = IRewardManager(rewardManager).mint(msg.sender, _pendingReward, true);
            require(success, "TOKEN_MINT_FAILED");
            emit Claim(msg.sender, pids, _pendingReward);
        }
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    function emergencyWithdraw(uint256 pid) external {

        require(pid < poolInfo.length, "POOL_DOES_NOT_EXIST");

        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount > 0, "AMOUNT_ZERO");

        // re-assign user amount to use in stakingToken.safeTransfer
        uint256 userAmount = user.amount;

        // decrease pool balance
        poolInfo[pid].tokenBalance -= userAmount;

        // reset user values
        user.amount = 0;
        user.rewardDebt = 0;

        // transfer to sender
        poolInfo[pid].stakingToken.safeTransfer(msg.sender, userAmount);
        emit EmergencyWithdraw(msg.sender, pid, userAmount);
    }

    /// @notice Internal function to check if a new emission rate is to be used from the emission rate schedule.
    function _updateEmissions() internal {
        uint256 length = emissionSchedule.length;
        if (length > 0 && (block.timestamp > startTime)) {
            // get the most recent emissionSchedule
            EmissionPoint memory emission = emissionSchedule[length - 1];
            // if the time is passed for this emissionSchedule
            // -> update rewardTokenPerInterval with new rate from rewardTokenPerInterval
            if (block.timestamp - startTime > emission.startTimeOffset) {
                this.massUpdatePools();
                rewardTokenPerInterval = uint256(emission.rewardsPerSecond);
                emissionSchedule.pop();
            }
        }
    }

    /// @notice External function to check if a new emission rate is to be used from the emission rate schedule.
    function updateEmissions() external {
        _updateEmissions();
    }

    /// @notice Update the existing emission rate schedule.
    /// @param _startTimeOffset The time, in seconds, of when the rate of the same index will take place.
    /// @param _rewardsPerSecond The rate at which reward tokens are emitted.
    function updateEmissionSchedule(uint128[] memory _startTimeOffset, uint128[] memory _rewardsPerSecond)
    external
    onlyOwner
    {
        require(
            _startTimeOffset.length == _rewardsPerSecond.length && _startTimeOffset.length == emissionSchedule.length,
            "INVALID_SCHEDULE"
            );
            
    unchecked {
        for (uint256 i = _startTimeOffset.length - 1; i + 1 != 0; i--) {
            emissionSchedule[_startTimeOffset.length - i - 1] = EmissionPoint({
            startTimeOffset : _startTimeOffset[i],
            rewardsPerSecond : _rewardsPerSecond[i]
            });
        }
    }
    }

    /// @notice Returns the current emission schedule.
    function getScheduleLength() external view returns (uint256) {
        return emissionSchedule.length;
    }

    /// @notice Updates a new starttime for staking emissions to begin.
    /// @notice Only update before start of farm
    function updateStartBlock(uint256 _startTime) external onlyOwner {
        require(block.timestamp < startTime, "STAKING_HAS_BEGUN");
        startTime = _startTime;
        emit StartBlockUpdated(_startTime);
    }

    /// @notice Withdraws ERC20 tokens that have been sent directly to the contract.
    function flushLostToken(uint256 pid) external onlyOwner nonReentrant {

        require(pid < poolInfo.length, "POOL_DOES_NOT_EXIST");
        PoolInfo memory pool = poolInfo[pid];
        uint256 amount = pool.stakingToken.balanceOf(address(this)) - pool.tokenBalance;
        if (amount > 0) {
            poolInfo[pid].stakingToken.safeTransfer(msg.sender, amount);
        }

        emit LostTokenFlushed(amount);
    }
}
