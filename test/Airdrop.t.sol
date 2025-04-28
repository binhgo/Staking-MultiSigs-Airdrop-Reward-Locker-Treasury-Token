// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "../Hevm.sol";
import "ds-test/test.sol";

import "../TreehouseToken.sol";
import "../Airdrop.sol";
import "../Treasury.sol";

/*
    root: 0xf2e940786c4ecce031844afad5e7e40993b5091c3e8e2281e88601d5b78f3496
    Tranche 0

    wid: 0xCe71065D4017F316EC606Fe4422e11eB2c47c246
    proof: [,
            ]


    wid: 0xAD75D37d1E45c18E5086eEc1B43450fDdACBF36A
    proof: [0xec5b5276f32407e4514d76f9edcc2591a6b60d08f2e3f12e30fc38e04600929d,
            0x6820dcd0fb5f3d899aec8ad82bfaecdbfbeba0c5651795073266f7cbfbd8f53d]


    wid: 0xd8847b08f13d1976aFEdAaB8A2c7f0349be63dce
    proof: [0x7ea519a93fe4cdb1430abc9a044c3a251428adf548a1cb9d8a216a07ad156fc2,
            0x6820dcd0fb5f3d899aec8ad82bfaecdbfbeba0c5651795073266f7cbfbd8f53d]


    wid: 0x9C62065Ee4A297d51227FE8707B18D3699e832C1
    proof: [0x6a74aef42c704d8ecb85415461fb6407b3d28e4476a3f96226ba28cfa04dae89,
            0x3a81437db16bb8917baa885cf48a518248186d0a845fb4f76ed562421c4a1445]

*/

uint256 constant ONE_TOKEN = 10**18;
uint256 constant ONE_YEAR = 31557600;

contract User {
    Airdrop air;

    function claim(
        address _air,
        uint256 _trancheId,
        uint256 _amount,
        bytes32[] memory _proofs
    ) public {
        air = Airdrop(_air);
        air.claim(_trancheId, _amount, _proofs);
    }
}

contract AirdropTest1 is Hevm, DSTest {
    User user1;
    User user2;
    User user3;
    User user4;

    Airdrop air;
    TreehouseToken token;
    Treasury treasury;

    bytes32 merkleRoot;
    bytes32[] internal user1Proof;
    bytes32[] internal user2Proof;
    bytes32[] internal user3Proof;
    bytes32[] internal user4Proof;

    function verifyProof(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf,
        uint256 index
    ) internal pure returns (bool) {
        bytes32 hash = leaf;
        for (uint256 i; i < proof.length; i++) {
            if (index % 2 == 0) {
                hash = keccak256(abi.encodePacked(hash, proof[i]));
            } else {
                hash = keccak256(abi.encodePacked(proof[i], hash));
            }

            index = index / 2;
        }

        return (hash == root);
    }

    function setUp() public {
        user1 = new User();
        user2 = new User();
        user3 = new User();
        user4 = new User();

        emit log_named_address("user1", address(user1));
        emit log_named_address("user2", address(user2));
        emit log_named_address("user3", address(user3));
        emit log_named_address("user4", address(user4));

        merkleRoot = 0x3f426b7b8146386a36637e9c1cccf1a84d225f9a201c07f460643c0a66232943;
        user1Proof = new bytes32[](2);
        user1Proof[
            0
        ] = 0x005a0033b5a1ac5c2872d7689e0f064ad6d2287ab98439e44c822e1c46530033;
        user1Proof[
            1
        ] = 0xb0c61396e0e3663f26609e87f0a825eb026af9738c0d180c803575e08f55e783;

        user2Proof = new bytes32[](2);
        user2Proof[
            0
        ] = 0xd8cc8d14a063bf449640b01c6fc2a27d23b7415fbfd3929f504cebea0fbc6724;
        user2Proof[
            1
        ] = 0xb0c61396e0e3663f26609e87f0a825eb026af9738c0d180c803575e08f55e783;

        user3Proof = new bytes32[](2);
        user3Proof[
            0
        ] = 0x5ccbd790c11abca18b5bb9bac70785e9c55c7ffb38dc44350a1b3b5d3c62a266;
        user3Proof[
            1
        ] = 0xb67b4f99456e52acf055737316a234bcb2ac39a859aebe6328411c565a2d6996;

        user4Proof = new bytes32[](2);
        user4Proof[
            0
        ] = 0x9871987435a2c7a270ecc93bbd1084f484bb1a6a6574bd38ecf0e4a826c56e65;
        user4Proof[
            1
        ] = 0xb67b4f99456e52acf055737316a234bcb2ac39a859aebe6328411c565a2d6996;

        token = new TreehouseToken("MyToken", "TKN");
        treasury = new Treasury("Treasury");
        air = new Airdrop(address(token), address(treasury));

        // get some tokens
        token.addAdmin(address(this));
        token.mint(100_000_000 * ONE_TOKEN);

        token.approve(address(air), 10_000_000 * ONE_TOKEN);

        // add one tranche
        air.newTranche(
            merkleRoot,
            400 * ONE_TOKEN,
            block.timestamp,
            block.timestamp + 3600,
            50
        );

        assertEq(address(user1), 0xCe71065D4017F316EC606Fe4422e11eB2c47c246);
        assertEq(address(user2), 0x185a4dc360CE69bDCceE33b3784B0282f7961aea);
        assertEq(address(user3), 0xEFc56627233b02eA95bAE7e19F648d7DcD5Bb132);
        assertEq(address(user4), 0xf5a2fE45F4f1308502b1C136b9EF8af136141382);
    }

    function test_newTranche() public {
        (
            uint256 startTime,
            uint256 endTime,
            uint256 penaltyRate,
            uint256 totalAllocation,
            uint256 claimed,
            bool isPaused
        ) = air.trancheReleases(0);

        assertEq(claimed, 0);
        assertEq(totalAllocation, 400 * ONE_TOKEN);
        assertTrue(!isPaused);

        assertEq(token.balanceOf(address(air)), 400 * ONE_TOKEN);
    }

    function test_newTranche1() public {
        air.newTranche(
            merkleRoot,
            400 * ONE_TOKEN,
            block.timestamp,
            block.timestamp + 3600,
            50
        );

        (
            uint256 startTime,
            uint256 endTime,
            uint256 penaltyRate,
            uint256 totalAllocation,
            uint256 claimed,
            bool isPaused
        ) = air.trancheReleases(1);

        assertEq(token.balanceOf(address(air)), 800 * ONE_TOKEN);
        assertEq(claimed, 0);
        assertEq(totalAllocation, 400 * ONE_TOKEN);
        assertTrue(!isPaused);
    }

    function test_claimNoPenalty() public {
        hevm.warp(block.timestamp + 3600 + 1);

        bytes32[] memory _user1Proof = user1Proof;
        bytes32[] memory _user2Proof = user2Proof;
        bytes32[] memory _user3Proof = user3Proof;
        bytes32[] memory _user4Proof = user4Proof;

        user1.claim(address(air), 0, 100 * ONE_TOKEN, _user1Proof);
        user2.claim(address(air), 0, 100 * ONE_TOKEN, _user2Proof);
        user3.claim(address(air), 0, 100 * ONE_TOKEN, _user3Proof);
        user4.claim(address(air), 0, 100 * ONE_TOKEN, _user4Proof);

        // air.claim(0, 100 * ONE_TOKEN, user1Proof);

        assertEq(token.balanceOf(address(user1)), 100 * ONE_TOKEN);
        assertEq(token.balanceOf(address(user2)), 100 * ONE_TOKEN);
        assertEq(token.balanceOf(address(user3)), 100 * ONE_TOKEN);
        assertEq(token.balanceOf(address(user4)), 100 * ONE_TOKEN);
    }

    function test_claimWithPenalty() public {
        hevm.warp(block.timestamp + 1500);

        (
            uint256 startTime,
            uint256 endTime,
            uint256 penaltyRate,
            uint256 totalAllocation,
            uint256 claimed,
            bool isPaused
        ) = air.trancheReleases(0);

        uint256 _penaltyMath = (penaltyRate * (block.timestamp - startTime)) /
            (endTime - startTime);

        uint256 _penaltyRate = _penaltyMath > penaltyRate
            ? 0
            : penaltyRate - _penaltyMath;

        uint256 penalty = (100 * ONE_TOKEN * _penaltyRate) / 100;
        uint256 claimable = 100 * ONE_TOKEN - penalty;

        // bytes32[] memory _user1Proof = user1Proof;
        // bytes32[] memory _user2Proof = user2Proof;
        // bytes32[] memory _user3Proof = user3Proof;
        // bytes32[] memory _user4Proof = user4Proof;

        user1.claim(address(air), 0, 100 * ONE_TOKEN, user1Proof);
        user2.claim(address(air), 0, 100 * ONE_TOKEN, user2Proof);
        user3.claim(address(air), 0, 100 * ONE_TOKEN, user3Proof);
        user4.claim(address(air), 0, 100 * ONE_TOKEN, user4Proof);

        assertEq(token.balanceOf(address(user1)), claimable);
        assertEq(token.balanceOf(address(user2)), claimable);
        assertEq(token.balanceOf(address(user3)), claimable);
        assertEq(token.balanceOf(address(user4)), claimable);

        assertEq(token.balanceOf(address(treasury)), penalty * 4);
    }

    function test_claimableBalanceFunc() public {
        hevm.warp(block.timestamp + 2000);
        (uint256 claimable, uint256 penalty) = air.claimableBalance(
            0,
            address(user1),
            100 * ONE_TOKEN
        );

        user1.claim(address(air), 0, 100 * ONE_TOKEN, user1Proof);
        assertEq(token.balanceOf(address(user1)), claimable);

        assertEq(token.balanceOf(address(treasury)), penalty);
    }

    // claim fail if provide incorrect merkle proofs
    function testFail_claim() public {
        bytes32[] memory proofs = user1Proof;
        air.claim(0, 100 * ONE_TOKEN, proofs);
    }

    function test_sweep() public {
        // test that owner is able to sweep the remaining amount of a tranche
        hevm.warp(block.timestamp +  ONE_YEAR + 1);
        emit log_named_uint("current time", block.timestamp);

        bytes32[] memory _user1Proof = user1Proof;
        bytes32[] memory _user2Proof = user2Proof;

        user1.claim(address(air), 0, 100 * ONE_TOKEN, _user1Proof);
        user2.claim(address(air), 0, 100 * ONE_TOKEN, _user2Proof);

        assertEq(token.balanceOf(address(user1)), 100 * ONE_TOKEN);
        assertEq(token.balanceOf(address(user2)), 100 * ONE_TOKEN);

        (
            uint256 startTime,
            uint256 endTime,
            uint256 penaltyRate,
            uint256 totalAllocation,
            uint256 claimed,
            bool isPaused
        ) = air.trancheReleases(0);

        emit log_named_uint("startTime", startTime);

        assertEq(totalAllocation, 400 * ONE_TOKEN);
        assertEq(claimed, 200 * ONE_TOKEN);

        air.sweep(0);

        assertEq(token.balanceOf(address(treasury)), 200 * ONE_TOKEN);

        (
            startTime,
            endTime,
            penaltyRate,
            totalAllocation,
            claimed,
            isPaused
        ) = air.trancheReleases(0);

        assertEq(claimed, 400 * ONE_TOKEN);
        assertEq(air.merkleRoots(0), bytes32(0));
    }

    // can not sweep 2 times on one tranche
    function testFail_sweep() public {
        // test that owner is able to sweep the remaining amount of a tranche
        hevm.warp(block.timestamp + 86400 * 365 + 1);

        bytes32[] memory _user1Proof = user1Proof;
        bytes32[] memory _user2Proof = user2Proof;

        user1.claim(address(air), 0, 100 * ONE_TOKEN, _user1Proof);
        user2.claim(address(air), 0, 100 * ONE_TOKEN, _user2Proof);

        assertEq(token.balanceOf(address(user1)), 100 * ONE_TOKEN);
        assertEq(token.balanceOf(address(user2)), 100 * ONE_TOKEN);

        (
            uint256 startTime,
            uint256 endTime,
            uint256 penaltyRate,
            uint256 totalAllocation,
            uint256 claimed,
            bool isPaused
        ) = air.trancheReleases(0);

        assertEq(totalAllocation, 400 * ONE_TOKEN);
        assertEq(claimed, 200 * ONE_TOKEN);

        air.sweep(0);
        assertEq(token.balanceOf(address(treasury)), 200 * ONE_TOKEN);

        (
            startTime,
            endTime,
            penaltyRate,
            totalAllocation,
            claimed,
            isPaused
        ) = air.trancheReleases(0);

        assertEq(claimed, 400 * ONE_TOKEN);
        assertEq(air.merkleRoots(0), bytes32(0));

        air.sweep(0);
    }

    // test sweep fail if call before (startTime + oneYear)
    function testFail_sweepSoon() public {
        hevm.warp(block.timestamp + 50000);
        air.sweep(0);
    }
}
