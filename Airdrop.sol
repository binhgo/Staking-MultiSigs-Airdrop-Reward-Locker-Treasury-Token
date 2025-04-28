// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Airdrop is Ownable {
    // Using
    using SafeERC20 for IERC20;

    // Tranche info
    struct TrancheRelease {
        uint256 startTime;       // start time of this tranche
        uint256 endTime;         // end time of this tranche
        uint256 penaltyRate;     // penalty rate if user withdraw before endTime
        uint256 totalAllocation; // total amount  allocated to this tranche
        uint256 claimed;         // total claimed amount of this tranche
        bool isPause;            // for security if there is issue
    }

    // oneYeat = 86400 * 365.25
    uint256 internal constant ONE_YEAR = 31557600;

    // penalty amount will go to rewardReserve (kind of treasury) when user withdraw sooner than endTime
    address public rewardReserve;

    // airdrop token
    IERC20 public immutable token;

    // current tranche
    uint256 public tranche;

    // tranche -> merkel root: store merkel root of this tranche
    mapping(uint256 => bytes32) public merkleRoots;

    // tranche => user => isClaimed
    mapping(uint256 => mapping(address => bool)) public claimed;

    // trancheId -> TrancheRelease
    mapping(uint256 => TrancheRelease) public trancheReleases;

    // Events
    event TrancheAdded(uint256 indexed tranche, bytes32 indexed merkleRoot, uint256 totalAmount);
    event TrancheExpired(uint256 indexed tranche);
    event Claimed(address indexed claimant, uint256 indexed tranche, uint256 claimedAmout, uint256 penaltyAmount);
    event Sweep(address indexed recipient, uint256 amount);
    event TranchePaused(uint256 indexed tranche);
    event TrancheUnpaused(uint256 indexed tranche);

    /**
     * @dev constructor
     * @param _token Token to airdrop
     * @param _rewardReserve Address of rewardReserve contract, penalty amount will go here
     */
    constructor(address _token, address _rewardReserve) {
        require(_rewardReserve != address(0), "ADDRESS_ZERO");
        require(_token != address(0), "ADDRESS_ZERO");

        token = IERC20(_token);
        rewardReserve = _rewardReserve;
    }

    /**
     * @dev setup a new tranche
     * @param _merkleRoot Merkel root of this tranche
     * @param _totalAllocation Total amount allocated to this tranche
     * @param _startTime Start time of this tranche
     * @param _endTime End time of this tranche
     * @param _penaltyRate Penalty rate if user withdraw before endtime
     */
    function newTranche(
        bytes32 _merkleRoot,
        uint256 _totalAllocation,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _penaltyRate
    ) external onlyOwner returns (uint256 trancheId) {

        require(_startTime < _endTime && _penaltyRate < 51, "INVALID_TRANCHE_RELEASE");

        trancheId = tranche;
        merkleRoots[trancheId] = _merkleRoot;

        trancheReleases[trancheId] = TrancheRelease({
        startTime : _startTime,
        endTime : _endTime,
        penaltyRate : _penaltyRate,
        totalAllocation : _totalAllocation,
        claimed : 0,
        isPause : false
        });

        tranche = trancheId + 1;

        token.safeTransferFrom(msg.sender, address(this), _totalAllocation);

        emit TrancheAdded(trancheId, _merkleRoot, _totalAllocation);
    }

    /**
     * @dev close a tranche
     * @param _trancheId ID of the tranche
     */
    function closeTranche(uint256 _trancheId) external onlyOwner {
        require(_trancheId < tranche, "TRANCHE_DOES_NOT_EXIST");

        merkleRoots[_trancheId] = bytes32(0);
        emit TrancheExpired(_trancheId);
    }

    /**
     * @dev pause a tranche
     * @param _trancheId ID of the tranche
     */
    function pauseTranche(uint256 _trancheId) external onlyOwner {
        require(_trancheId < tranche, "TRANCHE_DOES_NOT_EXIST");
        require(!trancheReleases[_trancheId].isPause, "TRANCHE_ALREADY_PAUSED");

        trancheReleases[_trancheId].isPause = true;
        emit TranchePaused(_trancheId);
    }

    /**
     * @dev un-pause a tranche
     * @param _trancheId ID of the tranche
     */
    function unpauseTranche(uint256 _trancheId) external onlyOwner {
        require(_trancheId < tranche, "TRANCHE_DOES_NOT_EXIST");
        require(trancheReleases[_trancheId].isPause, "TRANCHE_NOT_PAUSED");

        trancheReleases[_trancheId].isPause = false;
        emit TrancheUnpaused(_trancheId);
    }

    /**
     * @dev set reward reserve address
     * @param _rewardReserve Address of rewardReserve contract, penalty amount will go here
     */
    function setRewardReserve(address _rewardReserve) external onlyOwner {
        require(_rewardReserve != address(0), "ADDRESS_ZERO");
        rewardReserve = _rewardReserve;
    }

    /**
     * @dev sweeps any remaining tokens after 1 year.
     * @param _trancheId ID of the tranche
     */
    function sweep(uint256 _trancheId) external onlyOwner {

        require(_trancheId < tranche, "TRANCHE_DOES_NOT_EXIST");

        TrancheRelease storage _tranche = trancheReleases[_trancheId];

        require(_tranche.startTime + ONE_YEAR < block.timestamp, "TOO_EARLY");

        uint256 totalAllocation = _tranche.totalAllocation;

        uint256 _amount = totalAllocation - _tranche.claimed;

        require(_amount > 0, "NOTHING_TO_SWEEP");

        _tranche.claimed = totalAllocation;

        // close the tranche after sweep all of its tokens
        merkleRoots[_trancheId] = bytes32(0);

        token.safeTransfer(rewardReserve, _amount);

        emit TrancheExpired(_trancheId);

        emit Sweep(rewardReserve, _amount);
    }

    /**
     * @dev claim token
     * @param _trancheId ID of the tranche
     * @param _amount amount to claim
     * @param _merkleProof Merkel proofs of this user of this tranche
     */
    function claim(
        uint256 _trancheId,
        uint256 _amount,
        bytes32[] memory _merkleProof
    ) external {

        require(_trancheId < tranche, "TRANCHE_DOES_NOT_EXIST");
        require(_amount > 0, "INVALID_AMOUNT");
        require(!trancheReleases[_trancheId].isPause, "PAUSED");
        require(merkleRoots[_trancheId] != bytes32(0), "TRANCHE_CLOSED");

        _claim(msg.sender, _trancheId, _amount, _merkleProof);
        _disburse(msg.sender, _trancheId, _amount);
    }

    /**
     * @dev verify if _walletAddress is qualified for the airdrop
     * @param _walletAddress Wallet address of user
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     * @param _merkleProof Merkel proofs of this user of this tranche
     */
    function verify(
        address _walletAddress,
        uint256 _tranche,
        uint256 _amount,
        bytes32[] memory _merkleProof
    ) external view returns (bool valid) {
        return _verify(_walletAddress, _tranche, _amount, _merkleProof);
    }

    /**
     * @dev return claimable amount and penalty amount.
     * @param _walletAddress Wallet address of user
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     */
    function claimableBalance(uint256 _tranche, address _walletAddress, uint256 _amount)
    external
    view
    returns (uint256 claimableAmount, uint256 penaltyAmount)
    {
        if (claimed[_tranche][_walletAddress]) {
            return (0, 0);
        }

        return _claimableBalance(_tranche, _amount);
    }

    /**
     * @dev return claimable amount and penalty amount.
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     */
    function _claimableBalance(uint256 _tranche, uint256 _amount)
    internal
    view
    returns (uint256 claimableAmount, uint256 penaltyAmount)
    {
        TrancheRelease memory tr = trancheReleases[_tranche];

        uint256 _penaltyMath = (tr.penaltyRate * (block.timestamp - tr.startTime)) / (tr.endTime - tr.startTime);

        uint256 _penaltyRate = _penaltyMath > tr.penaltyRate ? 0 : tr.penaltyRate - _penaltyMath;

        if (_penaltyRate == 0) {
            claimableAmount = _amount;
        } else {
            claimableAmount = _amount - (_amount * _penaltyRate) / 100;
            penaltyAmount = _amount - claimableAmount;
        }
    }

    /**
     * @dev claim token.
     * @param _walletAddress Wallet address of user
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     * @param _merkleProof Merkel proofs of this user of this tranche
     */
    function _claim(
        address _walletAddress,
        uint256 _tranche,
        uint256 _amount,
        bytes32[] memory _merkleProof
    ) private {

        require(!claimed[_tranche][_walletAddress], "ALREADY_CLAIMED");

        require(_verify(_walletAddress, _tranche, _amount, _merkleProof), "INCORRECT_PROOF");

        claimed[_tranche][_walletAddress] = true;

        TrancheRelease storage _tr = trancheReleases[_tranche];
        _tr.claimed += _amount;
    }

    /**
     * @dev verify if _walletAddress is qualified for the airdrop.
     * @param _walletAddress Wallet address of user
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     * @param _merkleProof Merkel proof of this user of this tranche
     */
    function _verify(
        address _walletAddress,
        uint256 _tranche,
        uint256 _amount,
        bytes32[] memory _merkleProof
    ) private view returns (bool valid) {
        bytes32 leaf = keccak256(abi.encodePacked(_walletAddress, _amount));
        return MerkleProof.verify(_merkleProof, merkleRoots[_tranche], leaf);
    }

    /**
     * @dev transfer/disburse token to user.
     * @param _to Wallet address of user
     * @param _tranche ID of the tranche
     * @param _amount amount to claim
     */
    function _disburse(
        address _to,
        uint256 _tranche,
        uint256 _amount
    ) private {
        (uint256 claimableAmount, uint256 penaltyAmount) = _claimableBalance(_tranche, _amount);

        if (penaltyAmount > 0) {
            token.safeTransfer(rewardReserve, penaltyAmount);
        }
        token.safeTransfer(_to, claimableAmount);

        emit Claimed(_to, _tranche, claimableAmount, penaltyAmount);
    }
}
