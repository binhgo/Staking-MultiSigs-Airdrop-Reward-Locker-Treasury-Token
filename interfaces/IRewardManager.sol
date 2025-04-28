// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IRewardManager {
    function addMinter(address _minter) external;

    function removeMinter(address _minter) external;

    function setPenaltyRate(uint256 _penaltyRate) external;

    function setLockDuration(uint256 _durationInSeconds) external;

    function mint(
        address user,
        uint256 amount,
        bool withPenalty
    ) external returns (bool);

    function withdrawUnlocked() external;

    function withdrawAmount(uint256 amount) external;

    function withdrawAll() external;

    function totalBalance(address user) external view returns (uint256 amount);

    function unlockTime(address user) external view returns (uint256 timestamp);

    function unlockedBalance(address user) external view returns (uint256 amount);

    function lockedBalance(address user) external view returns (uint256 amount);

    function withdrawableBalance(address user) external view returns (uint256 amount, uint256 penalizedAmount);
}
