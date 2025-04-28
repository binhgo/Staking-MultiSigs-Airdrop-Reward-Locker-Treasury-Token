// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ITreehouseToken.sol";

contract RewardManager is Ownable, ReentrancyGuard {
    // user balance
    struct Balance {
        uint256 total; // user total amount: locked + unlocked
        uint256 unlocked; // only unlocked amount
    }

    // lock info
    struct Lock {
        uint256 amount; // lock amount
        uint256 unlockTime; // time to unlock
    }

    uint256 internal constant LOCK_LENGTH = 13;

    // pause for security reason
    bool public paused;

    // token to reward
    address public immutable rewardToken;

    // treasury: penalty amount will go here
    address public immutable rewardReserve;

    // 1 week time
    uint256 public constant ONE_WEEK = 86400 * 7;

    // lock duration: 12 weeks
    uint256 public lockDuration = ONE_WEEK * 12;

    // start time: thursday 12:00 first week...
    uint256 public immutable startTime;

    // penalty rate applied when user withdraw sooner
    uint256 public penaltyRate;

    // store total amount
    uint256 public totalSupply;

    // store locked amount
    uint256 public lockedSupply;

    // user -> balance
    mapping(address => Balance) public balances;

    // user -> lock
    // when claiming from Staking, amount will be locked for 12 weeks
    mapping(address => Lock[LOCK_LENGTH]) public locks;

    // only minter can mint token
    mapping(address => bool) public minter;

    // events
    event Withdraw(address indexed user, uint256 amount, uint256 penalty);
    event PauseContract(uint256 indexed timestamp);
    event UnpauseContract(uint256 indexed timestamp);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event PenaltyRateSet(uint256 indexed penaltyRate);
    event LockDurationSet(uint256 indexed duration);

    /**
     * @dev Throws if called when contract is paused.
     */
    modifier pausable() {
        require(!paused, "PAUSED");
        _;
    }

    /**
     * @dev constructor
     * @param _rewardToken Token to reward
     * @param _rewardReserve Address of rewardReserve contract, penalty amount will go here
     * @param _penaltyRate Penalty rate when user withdraw sooner
     */
    constructor(
        address _rewardToken,
        address _rewardReserve,
        uint256 _penaltyRate
    ) {
        require(_rewardToken != address(0), "ADDRESS_ZERO_REWARD_TOKEN");
        require(_rewardReserve != address(0), "ADDRESS_ZERO_REWARD_RESERVE");

        rewardToken = _rewardToken;
        rewardReserve = _rewardReserve;
        _setPenaltyRate(_penaltyRate);
        startTime = ((block.timestamp / ONE_WEEK) * ONE_WEEK);
    }

    /**
     * @dev Pause functions
     */
    function pause() external onlyOwner {
        paused = true;
        emit PauseContract(block.timestamp);
    }

    /**
     * @dev Unpause functions
     */
    function unpause() external onlyOwner {
        paused = false;
        emit UnpauseContract(block.timestamp);
    }

    function addMinter(address _minter) external onlyOwner {
        minter[_minter] = true;
        emit MinterAdded(_minter);
    }

    function removeMinter(address _minter) external onlyOwner {
        delete minter[_minter];
        emit MinterRemoved(_minter);
    }

    /**
     * @dev External function update penalty rate
     * @param _penaltyRate New penalty rate, must < 51%
     */
    function setPenaltyRate(uint256 _penaltyRate) external onlyOwner {
        _setPenaltyRate(_penaltyRate);
    }

    /**
     * @dev internal function update penalty rate
     * @param _penaltyRate New penalty rate, must < 51%
     */
    function _setPenaltyRate(uint256 _penaltyRate) internal {
        require(_penaltyRate < 51, "INVALID_RATE");
        penaltyRate = _penaltyRate;
        emit PenaltyRateSet(_penaltyRate);
    }

    /**
     * @dev update lock duration
     * @param _durationInSeconds New lock duration, must <= 12 weeks
     */
    function setLockDuration(uint256 _durationInSeconds) external onlyOwner {
        require(_durationInSeconds < ONE_WEEK * 12 + 1, "INVALID_DURATION_TOO_SHORT");

        // duration must be a multiple of one week
        require(_durationInSeconds % ONE_WEEK == 0, "INVALID_DURATION_NOT_MULTIPLE");

        lockDuration = _durationInSeconds;
        emit LockDurationSet(_durationInSeconds);
    }

    /**
     * @dev mint tokens to this contract. called by Staking contract
     * @param user Beneficial user
     * @param amount Amount to mint
     * @param withPenalty Is this amount subject to penalty
     */
    function mint(
        address user,
        uint256 amount,
        bool withPenalty
    ) external pausable returns (bool) {
        require(minter[msg.sender], "UNAUTHORIZED");
        if (amount == 0) return false;

        Balance storage bal = balances[user];
        if (withPenalty) {
            uint256 currentWeek = ((block.timestamp / ONE_WEEK) * ONE_WEEK);
            uint256 _unlockTime = currentWeek + lockDuration;
            uint256 totalDuration = (currentWeek - startTime) / ONE_WEEK;
            uint256 arrayPlace = totalDuration % 12;
            Lock storage loc = locks[user][arrayPlace];
            if (loc.unlockTime < _unlockTime) {
                // unlock some locked tokens
                bal.unlocked = bal.unlocked + loc.amount;

                // add the new locked tokens to lockedSupply and
                // subtract those unlocked tokens above from lockedSupply
                lockedSupply = lockedSupply + amount - loc.amount;

                loc.amount = amount;
                loc.unlockTime = _unlockTime;
            } else {
                loc.amount = loc.amount + amount;
                lockedSupply = lockedSupply + amount;
            }
        } else {
            bal.unlocked = bal.unlocked + amount;
        }
        bal.total = bal.total + amount;
        totalSupply = totalSupply + amount;

        bool success = ITreehouseToken(rewardToken).mintTo(address(this), amount);
        require(success, "MINT_FAILED");

        return true;
    }

    /**
     * @dev withdraw unlocked amount to sender (amount that pass the lock duration)
     */
    function withdrawUnlocked() external pausable nonReentrant {
        Balance storage bal = balances[msg.sender];
        require(bal.total > 0, "NO_REWARDS");

        Lock[LOCK_LENGTH] storage loc = locks[msg.sender];
        uint256 amount;
        for (uint256 i; i < LOCK_LENGTH; i++) {
            if (loc[i].unlockTime <= block.timestamp && loc[i].unlockTime != 0) {
                amount = amount + loc[i].amount;
                delete loc[i];
            }
        }

        if (amount > 0) {
            lockedSupply = lockedSupply - amount;
        }
        amount = amount + bal.unlocked;

        require(amount > 0, "ZERO_UNLOCKED");

        delete bal.unlocked;
        bal.total = bal.total - amount;
        totalSupply = totalSupply - amount;

        bool success = ITreehouseToken(rewardToken).transfer(msg.sender, amount);
        require(success, "TRANSFER_FAILED");

        emit Withdraw(msg.sender, amount, 0);
    }

    /**
     * @dev withdraw all amount: locked amount + unlocked amount.
     * unlocked amount: can withdraw all without penalty
     * locked amount: can withdraw with penalty rate applied
     * penalizedAmount will be sent to rewardReserve
     */
    function withdrawAll() external pausable nonReentrant {
        Balance storage bal = balances[msg.sender];
        require(bal.total > 0, "NO_REWARDS");
        uint256 penalizedAmount;
        uint256 locked;
        uint256 claimableAmount = bal.unlocked;
        Lock[LOCK_LENGTH] storage loc = locks[msg.sender];
        for (uint256 i; i < LOCK_LENGTH; i++) {
            if (loc[i].amount == 0) continue;
            if (loc[i].unlockTime <= block.timestamp) {
                claimableAmount = claimableAmount + loc[i].amount;
                locked = locked + loc[i].amount;
                delete loc[i];
            }
            if (loc[i].unlockTime > block.timestamp) {
                uint256 penalty = (loc[i].amount * penaltyRate) / 100;
                claimableAmount = claimableAmount + (loc[i].amount - penalty);
                penalizedAmount = penalizedAmount + penalty;
                locked = locked + loc[i].amount;
                delete loc[i];
            }
        }
        totalSupply = totalSupply - bal.total;
        lockedSupply = lockedSupply - locked;
        delete bal.total;
        delete bal.unlocked;

        bool success = ITreehouseToken(rewardToken).transfer(rewardReserve, penalizedAmount);
        require(success, "TRANSFER_FAILED_REWARD_RESERVE");

        success = ITreehouseToken(rewardToken).transfer(msg.sender, claimableAmount);
        require(success, "TRANSFER_FAILED_MSG_SENDER");

        emit Withdraw(msg.sender, claimableAmount, penalizedAmount);
    }

    /**
     * @dev return total balance of a user
     * @param user User address
     */
    function totalBalance(address user) external view returns (uint256 amount) {
        return balances[user].total;
    }

    /**
     * @dev return unlocked amount of a user
     * @param user User address
     */
    function unlockedBalance(address user) external view returns (uint256 amount) {
        Balance memory bal = balances[user];
        amount = bal.unlocked;
        Lock[LOCK_LENGTH] memory loc = locks[user];
        for (uint256 i; i < LOCK_LENGTH; i++) {
            if (loc[i].unlockTime != 0 && loc[i].unlockTime <= block.timestamp) {
                amount = amount + loc[i].amount;
            }
        }
    }

    /**
     * @dev return locked amount of a user
     * @param user User address
     */
    function lockedBalance(address user) external view returns (uint256 amount) {
        Lock[LOCK_LENGTH] memory loc = locks[user];
        for (uint256 i; i < LOCK_LENGTH; i++) {
            if (loc[i].unlockTime > block.timestamp) {
                amount = amount + loc[i].amount;
            }
        }
    }

    /**
     * @dev return withdraw-able amount of a user:
     * unlocked amount + (locked amount - penalizedAmount)
     * @param user User address
     */
    function withdrawableBalance(address user) external view returns (uint256 totalAmount, uint256 penalizedAmount) {
        Balance memory bal = balances[user];
        totalAmount = bal.unlocked;
        Lock[LOCK_LENGTH] memory loc = locks[user];
        for (uint256 i; i < LOCK_LENGTH; i++) {
            if (loc[i].amount == 0) continue;
            if (loc[i].unlockTime <= block.timestamp) {
                totalAmount = totalAmount + loc[i].amount;
            }
            if (loc[i].unlockTime > block.timestamp) {
                uint256 penalty = (loc[i].amount * penaltyRate) / 100;
                totalAmount = totalAmount + (loc[i].amount - penalty);
                penalizedAmount = penalizedAmount + penalty;
            }
        }
    }
}
