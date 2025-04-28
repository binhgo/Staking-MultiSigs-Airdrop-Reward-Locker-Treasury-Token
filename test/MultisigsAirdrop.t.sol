//SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../Airdrop.sol";
import "../MultiSigs.sol";
import "../TreehouseToken.sol";
import "../Treasury.sol";

import "ds-test/test.sol";
import "../Hevm.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

uint256 constant ONE_DAY = 86400;
uint8 constant NUM_CONFIRMATION = 3;
uint256 constant MIN_DELAY = ONE_DAY;

uint256 constant ONE_TOKEN = 10**18;

contract Owner {
    MultiSigs sigs;

    receive() external payable {}

    function submitTransaction(
        address _sigs,
        address _to,
        uint256 _value,
        bytes memory _data,
        uint256 _delay,
        bool _isUrgent
    ) public {
        sigs = MultiSigs(payable(_sigs));

        sigs.submitTransaction("name", _to, _value, _data, _delay, _isUrgent);
    }

    function confirmTransaction(address _sigs, uint256 _txIndex) public {
        sigs = MultiSigs(payable(_sigs));

        sigs.confirmTransaction(_txIndex);
    }

    function rejectTransaction(address _sigs, uint256 _txIndex) public {
        sigs = MultiSigs(payable(_sigs));

        sigs.rejectTransaction(_txIndex);
    }

    function executeTransaction(address _sigs, uint256 _txIndex) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.executeTransaction(_txIndex);
    }

    function revokeConfirmation(address _sigs, uint256 _txIndex) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.revokeConfirmation(_txIndex);
    }

    function revokeRejection(address _sigs, uint256 index) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.revokeRejection(index);
    }

    function addOwner(address _sigs, address _newOwner) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.addOwner(_newOwner);
    }

    function removeOwner(address _sigs, address _newOwner) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.removeOwner(_newOwner);
    }

    function setNumConfirmationsRequired(address _sigs, uint8 _newNum) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.setNumConfirmationsRequired(_newNum);
    }
}

contract TestMultisigAirdrop is DSTest, Hevm {
    TreehouseToken token;
    Treasury treasury;
    Airdrop air;
    MultiSigs sigs;

    Owner owner1;
    Owner owner2;
    Owner owner3;

    function setUp() public {
        token = new TreehouseToken("MyToken", "THF");
        treasury = new Treasury("treasury");
        air = new Airdrop(address(token), address(treasury));

        owner1 = new Owner();
        owner2 = new Owner();
        owner3 = new Owner();

        address[] memory ownerList = new address[](3);

        ownerList[0] = address(owner1);
        ownerList[1] = address(owner2);
        ownerList[2] = address(owner3);

        sigs = new MultiSigs(ownerList, NUM_CONFIRMATION, MIN_DELAY);
        token.addAdmin(address(sigs));
        token.transferOwnership(address(sigs));
    }

    function test_mint(uint224 amount) public {
        if (amount > token.maxSupply()) return;

        bytes memory payload = abi.encodeWithSignature("mint(uint256)", amount);
        owner1.submitTransaction(
            address(sigs),
            address(token),
            0,
            payload,
            ONE_DAY,
            false
        );

        owner2.confirmTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY + 1);
        owner1.executeTransaction(address(sigs), 0);

        assertEq(token.balanceOf(address(sigs)), amount);
    }
}
