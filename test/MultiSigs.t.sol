// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../Hevm.sol";
import "ds-test/test.sol";
import "ds-note/note.sol";

import "../Staking.sol";
import "../RewardManager.sol";
import "../TreehouseToken.sol";
// import "./Treasury.sol";

import "../MultiSigs.sol";

uint256 constant ONE_DAY = 86400;
uint256 constant MIN_DELAY = ONE_DAY;

uint256 constant ONE_TOKEN = 10**18;
uint8 constant NUM_CONFIRMATION = 3;

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

contract MultisigsTest1 is DSTest, DSNote, Hevm {
    MultiSigs sigs;
    TreehouseToken myToken;

    Owner owner1;
    Owner owner2;
    Owner owner3;

    function setUp() public {
        owner1 = new Owner();
        owner2 = new Owner();
        owner3 = new Owner();

        address[] memory ownerList = new address[](3);

        ownerList[0] = address(owner1);
        ownerList[1] = address(owner2);
        ownerList[2] = address(owner3);

        sigs = new MultiSigs(ownerList, NUM_CONFIRMATION, MIN_DELAY);
        myToken = new TreehouseToken("Treehouse", "THF");
        myToken.addAdmin(address(sigs));
        myToken.transferOwnership(address(sigs));
    }

    function test_addOwner(address _newOwner) public {
        if (sigs.isOwner(_newOwner) || _newOwner == address(0)) {
            return;
        }
        // submit a new transaction to add owner4
        bytes memory payload = abi.encodeWithSignature(
            "addOwner(address)",
            _newOwner
        );
        owner1.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            false
        );

        owner2.confirmTransaction(address(sigs), 0);

        owner3.confirmTransaction(address(sigs), 0);

        // travel to the point after the transaction delay
        hevm.warp(block.timestamp + ONE_DAY * 3);

        owner2.executeTransaction(address(sigs), 0);

        assertTrue(sigs.isOwner(address(_newOwner)));
    }

    function test_removeOwner() public {
        bytes memory payload = abi.encodeWithSignature(
            "removeOwner(address)",
            address(owner1)
        );
        // (bool success, ) = address(sigs).call{value:ONE_TOKEN*10}("");
        // require(success, "send ether failed");
        owner2.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            true
        );
        owner3.confirmTransaction(address(sigs), 0);

        // assert that owner1 is an owner
        assertTrue(sigs.isOwner(address(owner1)));

        owner1.rejectTransaction(address(sigs), 0);

        owner2.executeTransaction(address(sigs), 0);

        // assert that owner1 is removed
        assertTrue(!sigs.isOwner(address(owner1)));

        address[] memory currentOwners = sigs.getOwners();
        uint256 len = currentOwners.length;
        for (uint256 i; i < len; i++) {
            assertTrue(!(currentOwners[i] == address(owner1)));
        }
    }

    function test_changeNumRequired() public {
        bytes memory payload = abi.encodeWithSignature(
            "setNumConfirmationsRequired(uint8)",
            2
        );

        owner1.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            true
        );

        assertEq(sigs.numConfirmationsRequired(), 3);

        owner2.confirmTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        owner3.executeTransaction(address(sigs), 0);

        assertEq(sigs.numConfirmationsRequired(), 2);
    }

    function testFail_changeNumRequired() public {
        bytes memory payload = abi.encodeWithSignature(
            "setNumConfirmationsRequired(uint8)",
            4
        );

        owner1.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            true
        );

        assertEq(sigs.numConfirmationsRequired(), 3);

        owner2.confirmTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        owner3.executeTransaction(address(sigs), 0);

        assertEq(sigs.numConfirmationsRequired(), 2);
    }

    function testFail_changeNumRequired1() public {
        bytes memory payload = abi.encodeWithSignature(
            "setNumConfirmationsRequired(uint8)",
            2
        );

        owner1.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            false
        );

        assertEq(sigs.numConfirmationsRequired(), 3);

        owner2.confirmTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        owner2.revokeConfirmation(address(sigs), 0);

        owner3.executeTransaction(address(sigs), 0);

        assertEq(sigs.numConfirmationsRequired(), 2);
    }

    function test_changeNumRequired2() public {
        bytes memory payload = abi.encodeWithSignature(
            "setNumConfirmationsRequired(uint8)",
            2
        );

        owner1.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload,
            ONE_DAY * 2,
            true
        );

        assertEq(sigs.numConfirmationsRequired(), 3);

        owner2.rejectTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        owner2.revokeRejection(address(sigs), 0);
        owner2.confirmTransaction(address(sigs), 0);

        owner3.executeTransaction(address(sigs), 0);

        assertEq(sigs.numConfirmationsRequired(), 2);
    }

    function testFail_addOwner(address _newOwner) public {
        owner1.addOwner(address(sigs), _newOwner);
    }

    function testFail_addOwner1(address _newOwner) public {
        sigs.addOwner(_newOwner);
    }

    function testFail_removeOwner() public {
        owner2.removeOwner(address(sigs), address(owner1));
    }

    function testFail_removeOwner1() public {
        sigs.removeOwner(address(owner1));
    }

    function testFail_setNumRequirement() public {
        owner3.setNumConfirmationsRequired(address(sigs), 2);
    }

    function testFail_setNumRequirement1() public {
        sigs.setNumConfirmationsRequired(2);
    }

    // this function test propose multiple transactions
    function test_multipleTransactions() public note {
        // 1. propose transaction 1 to mint 1000 tokens to the multisig contract
        // 2. propose transaction 2 to remove admin 3
        // 3. execute transaction 2
        // 4. execute transaction 1
        // 5. propose transaction 3 to send 500 tokens to owner1
        // 6. propose transaction 4 to send 500 tokens to owner2
        // 6. execute transaction 3
        // 7. execute transaction 4

        bytes memory payload0 = abi.encodeWithSignature(
            "mint(uint256)",
            1000 * ONE_TOKEN
        );
        bytes memory payload1 = abi.encodeWithSignature(
            "removeOwner(address)",
            address(owner3)
        );
        bytes memory payload2 = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(owner1),
            500 * ONE_TOKEN
        );
        bytes memory payload3 = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(owner2),
            500 * ONE_TOKEN
        );

        owner1.submitTransaction(
            address(sigs),
            address(myToken),
            0,
            payload0,
            block.timestamp + ONE_DAY * 6,
            false
        );

        owner2.submitTransaction(
            address(sigs),
            address(sigs),
            0,
            payload1,
            block.timestamp + ONE_DAY * 2,
            true
        );

        owner1.confirmTransaction(address(sigs), 1);
        owner2.executeTransaction(address(sigs), 1);

        // assert that owner3 is removed
        assertTrue(!sigs.isOwner(address(owner3)));

        address[] memory currentOwners = sigs.getOwners();
        uint256 len = currentOwners.length;
        for (uint256 i; i < len; i++) {
            assertTrue(!(currentOwners[i] == address(owner3)));
        }

        owner2.confirmTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY * 8);

        owner1.executeTransaction(address(sigs), 0);
        assertEq(myToken.balanceOf(address(sigs)), 1000 * ONE_TOKEN);

        owner1.submitTransaction(
            address(sigs),
            address(myToken),
            0,
            payload2,
            block.timestamp + 2 * ONE_DAY,
            false
        );
        owner2.confirmTransaction(address(sigs), 2);

        owner2.submitTransaction(
            address(sigs),
            address(myToken),
            0,
            payload3,
            block.timestamp + 2 * ONE_DAY,
            false
        );

        owner1.confirmTransaction(address(sigs), 3);

        hevm.warp(block.timestamp + ONE_DAY * 40);

        assertEq(myToken.balanceOf(address(sigs)), 1000 * ONE_TOKEN);

        owner1.executeTransaction(address(sigs), 2);
        owner2.executeTransaction(address(sigs), 3);

        assertEq(myToken.balanceOf(address(owner1)), 500 * ONE_TOKEN);
        assertEq(myToken.balanceOf(address(owner2)), 500 * ONE_TOKEN);
    }

    // test withdraw ether from mutlsig
    function test_withdrawEther() public {
        address(sigs).call{value: 100 ether}("");
        assertEq(address(sigs).balance, 100 ether);

        // owner1 propose withdraw to his address 10 ether
        owner1.submitTransaction(
            address(sigs),
            address(owner1),
            10 ether,
            bytes(""),
            ONE_DAY,
            false
        );
        owner2.confirmTransaction(address(sigs), 0);
        owner3.confirmTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY + 1);

        owner1.executeTransaction(address(sigs), 0);

        assertEq(address(owner1).balance, 10 ether);

        assertEq(address(sigs).balance, 90 ether);
    }
}
