// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "ds-test/test.sol";
import "../MultiSigs.sol";
import "../TreehouseToken.sol";
import "../Hevm.sol";

uint256 constant ONE_DAY = 86400;
uint8 constant NUM_CONFIRMATION = 3;
uint256 constant MIN_DELAY = ONE_DAY;

uint256 constant ONE_TOKEN = 10**18;

contract Owner {
    MultiSigs sigs;

    receive() external payable {}

    function sendTransaction(
        address _sigs,
        address _to,
        uint256 _value,
        bytes memory _data,
        uint256 _delay,
        bool _isUrgent
    ) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.submitTransaction("anme", _to, _value, _data, _delay, _isUrgent);
    }

    function approveTransaction(address _sigs, uint256 index) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.confirmTransaction(index);
    }

    function executeTransaction(address _sigs, uint256 index) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.executeTransaction(index);
    }

    function rejectTransaction(address _sigs, uint256 index) public {
        sigs = MultiSigs(payable(_sigs));
        sigs.rejectTransaction(index);
    }
}

contract MultisigTokenTest is DSTest, Hevm {
    TreehouseToken myToken;
    MultiSigs sigs;

    Owner owner1;
    Owner owner2;
    Owner owner3;

    function setUp() public {
        myToken = new TreehouseToken("MyToken", "MTK");

        owner1 = new Owner();
        owner2 = new Owner();
        owner3 = new Owner();

        address[] memory ownerList = new address[](3);
        ownerList[0] = address(owner1);
        ownerList[1] = address(owner2);
        ownerList[2] = address(owner3);

        sigs = new MultiSigs(ownerList, NUM_CONFIRMATION, MIN_DELAY);

        // allow sigs contract to mint tokens
        myToken.addAdmin(address(sigs));
        myToken.addAdmin(address(this));

        // give some ethers to the multisigs contract
        payable(address(sigs)).call{value: 10 ether}("");

        // transfer ownership to the sigs contract
        myToken.transferOwnership(address(sigs));
    }

    //expect success if mint token using the sigs contract
    function test_mintToken(uint256 amount) public {
        if (amount > myToken.maxSupply()) {
            return;
        }

        // owner1 send a request to mint 1000 tokens to his contract
        bytes memory payload = abi.encodeWithSignature("mint(uint256)", amount);
        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );

        // approve the transaction
        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        // fast forward 3 days
        hevm.warp(block.timestamp + ONE_DAY * 3);

        // execute transaction
        owner1.executeTransaction(address(sigs), 0);

        // assert that owner1 has 1000 tokens in myToken contract

        assertEq(myToken.balanceOf(address(sigs)), uint256(amount));
    }

    function test_MintToToken(uint256 amount) public {
        if (amount > myToken.maxSupply()) {
            return;
        }

        // owner1 send a request to mint 1000 tokens to his contract
        bytes memory payload = abi.encodeWithSignature(
            "mintTo(address,uint256)",
            address(owner1),
            amount
        );
        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );

        // approve the transaction
        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        // fast forward 3 days
        hevm.warp(block.timestamp + ONE_DAY * 3);

        // execute transaction
        owner1.executeTransaction(address(sigs), 0);

        // assert that owner1 has 1000 tokens in myToken contract
        assertEq(myToken.balanceOf(address(owner1)), amount);
    }

    function test_burnToken(uint256 amount) public {
        if (amount > myToken.maxSupply()) return;

        // mint to multisig contract 1000 tokens
        myToken.mintTo(address(sigs), amount);
        assertEq(myToken.balanceOf(address(sigs)), amount);

        // burn all token of sigs contract
        bytes memory payload = abi.encodeWithSignature("burn(uint256)", amount);
        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + 2 * ONE_DAY,
            false
        );

        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        hevm.warp(ONE_DAY * 3);

        owner1.executeTransaction(address(sigs), 0);

        assertEq(myToken.balanceOf(address(sigs)), 0);
    }

    function test_addAdmin() public {
        // request to add owner4 to be an admin of the token contract
        Owner owner4 = new Owner();

        bytes memory payload = abi.encodeWithSignature(
            "addAdmin(address)",
            address(owner4)
        );

        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            true
        );

        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY * 3);

        owner1.executeTransaction(address(sigs), 0);

        assertTrue(myToken.admins(address(owner4)));
    }

    function test_addAdmin1() public {
        // request to add owner4 to be an admin of the token contract
        Owner owner4 = new Owner();

        bytes memory payload = abi.encodeWithSignature(
            "addAdmin(address)",
            address(owner4)
        );

        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );

        // owner2.approveTransaction(address(sigs), 0);
        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY * 3);

        owner1.executeTransaction(address(sigs), 0);

        // assertTrue(myToken.admins(address(owner4)));
    }

    function testFail_RemoveAdmin() public {
        bytes memory payload = abi.encodeWithSignature(
            "removeAdmin(address)",
            address(this)
        );

        owner1.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + 2 * ONE_DAY,
            false
        );
        owner2.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY * 3);

        owner3.executeTransaction(address(sigs), 0);

        myToken.mint(1000 * ONE_TOKEN);
    }

    function test_setSupplyIncrease(uint8 newSupply) public {
        if (newSupply > 100 || newSupply == 0) return;

        bytes memory payload = abi.encodeWithSignature(
            "setSupplyIncreaseRate(uint256)",
            uint256(newSupply)
        );

        owner2.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );
        owner1.approveTransaction(address(sigs), 0);
        owner3.approveTransaction(address(sigs), 0);

        hevm.warp(ONE_DAY * 3);
        owner1.executeTransaction(address(sigs), 0);

        assertEq(myToken.supplyIncreaseRate(), uint256(newSupply));
    }

    function testFail_setMaxSupply(uint256 newMaxSupply) public {
        bytes memory payload = abi.encodeWithSignature(
            "setMaxSupply(uint256)",
            newMaxSupply
        );

        owner3.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );

        owner1.rejectTransaction(address(sigs), 0);
        owner2.approveTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + ONE_DAY * 3);

        owner2.executeTransaction(address(sigs), 0);
    }

    function test_setMaxSupply() public {
        uint224 newMaxSupply = myToken.maxSupply() + (myToken.maxSupply() * 1) / 100;
        uint224 secondMaxSupply = newMaxSupply + newMaxSupply / 100;

        bytes memory payload = abi.encodeWithSignature(
            "setMaxSupply(uint224)",
            newMaxSupply
        );

        owner3.sendTransaction(
            address(sigs),
            address(myToken),
            0,
            payload,
            block.timestamp + ONE_DAY * 2,
            false
        );

        owner1.approveTransaction(address(sigs), 0);
        owner2.approveTransaction(address(sigs), 0);

        hevm.warp(block.timestamp + 31557600 * 4 + 1);

        owner2.executeTransaction(address(sigs), 0);

        assertEq(myToken.maxSupply(), newMaxSupply);

    }
}
