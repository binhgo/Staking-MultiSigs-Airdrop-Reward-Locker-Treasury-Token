// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ITreehouseToken {
    function mint(uint256 _amount) external returns (bool);

    function mintTo(address _recipient, uint256 _amount) external returns (bool);

    function burn(uint256 _amount) external returns (bool);

    function addAdmin(address _admin) external;

    function removeAdmin(address _admin) external;

    function setSupplyIncreaseRate(uint256 _rate) external;

    function setMaxSupply(uint224 _maxTokenSupply) external;

    function transfer(address recipient, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}
