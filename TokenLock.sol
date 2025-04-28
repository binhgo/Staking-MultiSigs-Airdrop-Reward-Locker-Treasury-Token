// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Time-locks tokens according to an unlock schedule
 */
contract TokenLock { 
    using SafeERC20 for IERC20;

    struct UnlockRate {
        uint256 timestamp;
        uint256 unlockPercentage;
    }

    IERC20 public immutable token;

    // The current unlock rate of this contract
    uint256 public currentUnlockRate;

    mapping(address => uint256) public lockedAmounts;
    mapping(address => uint256) public claimedAmounts;

    UnlockRate[] public unlockRates;

    event Locked(address indexed sender, address[] indexed recipients, uint256[] amounts);
    event Claimed(address indexed owner, uint256 amount);
    event CurrentUnlockRateUpdated(uint256 currentUnlockRate);

    /**
     * @dev Constructor
     * @param _token The token address this contract will lock
     * @param _unlockTimestamps The array of timestamps when a new unlock rate is released
     * @param _unlockRates The unlock rates that will be released on its unlockTimestamp
     */
    constructor(
        address _token,
        uint256[] memory _unlockTimestamps,
        uint256[] memory _unlockRates
    ) {

        require(_token != address(0), "TOKEN_ADDRESS_0");

        // check inputs
        require(_unlockTimestamps.length == _unlockRates.length, "INVALID_ARRAY_LENGTH");

        require(_unlockTimestamps.length > 0, "EMPTY_ARRAY");

        uint256 t = _unlockTimestamps[0];
        uint256 totalUnlockRates = _unlockRates[0];
        for (uint256 i = 1; i < _unlockTimestamps.length; i++) {
            require(_unlockTimestamps[i] > t, "INVALID_TIMESTAMP");
            totalUnlockRates += _unlockRates[i];
            t = _unlockTimestamps[i];
        }

        require(totalUnlockRates == 100, "INVALID_UNLOCK_RATE");

        token = IERC20(_token);

        // save inputs to state variables
        unchecked {
            for (uint256 i = _unlockTimestamps.length - 1; i + 1 != 0; i--) {
                unlockRates.push(UnlockRate({ timestamp: _unlockTimestamps[i], unlockPercentage: _unlockRates[i] }));
            }
        }
    }

    /**
     * @dev lock tokens to the benefit of recipients
     * @param recipients The accounts that are having tokens locked
     * @param amounts The amounts of tokens to lock per account
     */
    function lock(address[] calldata recipients, uint256[] calldata amounts) external {

        // if the unlockRates array is empty, then the unlock ended.
        require(unlockRates.length > 0, "UNLOCK_PERIOD_ENDED");

        require(recipients.length > 0, "EMPTY_ARRAY");

        require(recipients.length == amounts.length, "INVALID_ARRAY_LENGTHS");

        
        uint256 amount = 0;
        for (uint256 i; i < recipients.length; i++) {
            lockedAmounts[recipients[i]] += amounts[i];
            amount += amounts[i];
        }

        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Locked(msg.sender, recipients, amounts);
    }

    /// @dev update the currentUnlockRate
    function updateCurrentUnlockRate() public {
        if (currentUnlockRate == 100) return;

        unchecked {
            for (uint256 i = unlockRates.length - 1; i + 1 != 0; i--) {
                UnlockRate memory rate = unlockRates[i];
                if (block.timestamp > rate.timestamp) {
                    currentUnlockRate += rate.unlockPercentage;
                    unlockRates.pop();
                    emit CurrentUnlockRateUpdated(currentUnlockRate);
                } else {
                    break;
                }
            }
        }
    }

    /**
     * @dev Claims the caller's tokens that have been unlocked
     */
    function claim() external {
        if (unlockRates.length > 0) {
            if (block.timestamp > unlockRates[unlockRates.length - 1].timestamp) {
                updateCurrentUnlockRate();
            }
        }

        uint256 claimable = _claimableBalance(msg.sender);
        if (claimable > 0) {
            claimedAmounts[msg.sender] += claimable;
            token.safeTransfer(msg.sender, claimable);
            emit Claimed(msg.sender, claimable);
        }
    }

    /**
     * @dev Returns the maximum number of tokens currently claimable by `owner`
     * @param owner The account to check the claimable balance of
     * @return The number of tokens currently claimable
     */
    function claimableBalance(address owner) external view returns (uint256) {
        uint256 locked = lockedAmounts[owner];
        uint256 claimed = claimedAmounts[owner];

        if (currentUnlockRate == 100) {
            return locked - claimed;
        }

        uint256 _currentUnlockRate = currentUnlockRate;

        unchecked {
            for (uint256 i = unlockRates.length - 1; i + 1 != 0; i--) {
                UnlockRate memory rate = unlockRates[i];
                if (block.timestamp > rate.timestamp) {
                    _currentUnlockRate += rate.unlockPercentage;
                } else {
                    break;
                }
            }
        }
        return (locked * _currentUnlockRate) / 100 - claimed;
    }

    /**
     * @dev Internally returns the maximum number of tokens currently claimable by `owner`
     * @param owner The account to check the claimable balance of
     * @return The number of tokens currently claimable
     */
    function _claimableBalance(address owner) internal view returns (uint256) {
        uint256 locked = lockedAmounts[owner];
        uint256 claimed = claimedAmounts[owner];
        if (currentUnlockRate == 100) {
            return locked - claimed;
        }
        return (locked * currentUnlockRate) / 100 - claimed;
    }

    function unlockRatesLength() external view returns(uint256) {
        return unlockRates.length;
    }
}
