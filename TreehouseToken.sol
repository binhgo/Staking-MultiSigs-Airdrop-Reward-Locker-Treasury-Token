// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TreehouseToken is ERC20Votes, Ownable {

    bool public paused;
    uint224 public maxSupply = 1_000_000_000 * 10**18;

    uint256 public supplyIncreaseRate = 1;
    uint256 public supplyIncreaseTimestamp;
    uint256 public constant TIME_INTERVAL = 31557600;

    mapping(address => bool) public admins;

    event AddAdmin(address indexed admin);
    event RemoveAdmin(address indexed admin);
    event PauseContract(uint256 indexed timestamp);
    event UnpauseContract(uint256 indexed timestamp);
    event MaxSupplySet(uint256 newMaxSupply);
    event SupplyIncreaseTimeStampSet(uint256 newTimestamp);

    /**
     * @dev Throws if called by any account other than an admin
     */
    modifier multiAdmin() {
        require(admins[msg.sender], "NOT_ADMIN");
        _;
    }

    /**
     * @dev The pause mechanism
     */
    modifier pausable() {
        require(!paused, "PAUSED");
        _;
    }

    constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) ERC20Permit(_name) {
        supplyIncreaseTimestamp = block.timestamp + TIME_INTERVAL * 3;
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
     * @notice Mint to msg.sender
     * @dev Only Admins
     * @param _amount amount of tokens to mint
     */
    function mint(uint256 _amount) external multiAdmin pausable returns (bool) {
        _mint(_msgSender(), _amount);
        return true;
    }

    /**
     * @notice Mint to _recipient
     * @dev Only Admins
     * @param _recipient address of the beneficiary
     * @param _amount amount of tokens to mint
     */
    function mintTo(address _recipient, uint256 _amount) external multiAdmin pausable returns (bool) {
        _mint(_recipient, _amount);
        return true;
    }

    /**
     * @notice Burn tokens of msg.sender
     * @dev Only Admins
     * @param _amount Amount of tokens to burn
     */
    function burn(uint256 _amount) external multiAdmin pausable returns (bool) {
        _burn(_msgSender(), _amount);
        return true;
    }

    /**
     * @notice Add admin. Typically a smart contract.
     * @dev Only Owner
     * @param _admin address of the admin
     */
    function addAdmin(address _admin) external onlyOwner {
        require(!admins[_admin], "ADMIN_ALREADY_SET");
        require(_admin != address(0), "ADDRESS_ZERO");
        
        admins[_admin] = true;
        emit AddAdmin(_admin);
    }

    /**
     * @notice Remove admin. Typically a smart contract.
     * @dev Only Owner
     * @param _admin address of the admin
     */
    function removeAdmin(address _admin) external onlyOwner {
        require(admins[_admin], "ADMIN_NOT_SET");
        delete admins[_admin];
        emit RemoveAdmin(_admin);
    }

    /**
     * @notice Set supply increase rate
     * @dev Only Owner
     * @param _rate uint256
     */
    function setSupplyIncreaseRate(uint256 _rate) external onlyOwner {
        require(_rate > 0 && _rate < 101, "INVALID_RATE");
        supplyIncreaseRate = _rate;
    }

    /**
     * @notice Set max supply
     * @dev Only Admins
     * @param _maxTokenSupply uint224
     */
    function setMaxSupply(uint224 _maxTokenSupply) external onlyOwner {
        require(block.timestamp >= supplyIncreaseTimestamp, "TOO_EARLY");
        require((maxSupply * supplyIncreaseRate) / 100 + maxSupply >= _maxTokenSupply, "EXCEEDS_ALLOWED_INCREASE");
        require(totalSupply() <= _maxTokenSupply, "SUBCEEDS_TOTAL_SUPPLY");
        maxSupply = _maxTokenSupply;
        supplyIncreaseTimestamp += TIME_INTERVAL;

        emit MaxSupplySet(_maxTokenSupply);
        emit SupplyIncreaseTimeStampSet(supplyIncreaseTimestamp);
    }

    /**
     * @dev Maximum token supply. Overrides function inherited from ERC20Votes.sol
     */
    function _maxSupply() internal view override returns (uint224) {
        return maxSupply;
    }
}
