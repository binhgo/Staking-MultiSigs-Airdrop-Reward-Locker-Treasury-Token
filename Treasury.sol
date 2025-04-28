// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @dev Treasury that allows owners to withdraw tokens and ETH
 */
contract Treasury is Ownable {
    using SafeERC20 for IERC20;

    string public name;
    bool public paused;

    mapping(address => bool) public admins;

    event AddAdmin(address indexed admin);
    event RemoveAdmin(address indexed admin);
    event NativeReceived(address indexed sender, uint256 indexed amount);
    event PauseContract(uint256 indexed timestamp);
    event UnpauseContract(uint256 indexed timestamp);
    event TokenTransfered(address indexed token, address indexed receiver, uint256 amount);

    /**
     * @dev Throws if called by any account other than an admin
     */
    modifier multiAdmin() {
        require(admins[_msgSender()], "NOT_ADMIN");
        _;
    }

    /**
     * @dev Throws if called by any account other than the admin.
     */
    modifier pausable() {
        require(!paused, "PAUSED");
        _;
    }

    constructor(string memory _name) {
        name = _name;
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        paused = true;
        emit PauseContract(block.timestamp);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        paused = false;
        emit UnpauseContract(block.timestamp);
    }

    /**
     * @notice Add admin. Typically a smart contract.
     * @dev Only Owner
     * @param _admin address
     */
    function addAdmin(address _admin) external onlyOwner {
        require(!admins[_admin], "ADMIN_ALREADY_SET");
        admins[_admin] = true;
        emit AddAdmin(_admin);
    }

    /**
     * @notice Remove admin. Typically a smart contract.
     * @dev Only Owner
     * @param _admin address
     */
    function removeAdmin(address _admin) external onlyOwner {
        require(admins[_admin], "ADMIN_NOT_SET");
        admins[_admin] = false;
        emit RemoveAdmin(_admin);
    }

    function withdrawToken(
        address token,
        uint256 amount
    ) external multiAdmin pausable {
        require(amount <= IERC20(token).balanceOf(address(this)), "INSUFFICIENT_AMOUNT");
        IERC20(token).safeTransfer(_msgSender(), amount);
        emit TokenTransfered(token, _msgSender(), amount);
    }

    function withdrawNative(uint256 amount) external multiAdmin pausable {
        require(amount <= address(this).balance, "INSUFFICIENT_FUNDS");
        (bool success, ) = _msgSender().call{ value: amount }("");
        require(success, "TRANSFER_FAILED");
    }

    receive() external payable {
        if (msg.value > 0) {
            emit NativeReceived(_msgSender(), msg.value);
        }
    }

    fallback() external payable {
        if (msg.value > 0) {
            emit NativeReceived(_msgSender(), msg.value);
        }
    }
}
