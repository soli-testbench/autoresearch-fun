// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {MockVerifier} from "../src/MockVerifier.sol";
import {IAttestationVerifier} from "../src/IAttestationVerifier.sol";

contract MockVerifierTest is Test {
    MockVerifier verifier;

    function setUp() public {
        verifier = new MockVerifier();
    }

    function test_implementsInterface() public view {
        // Confirm it can be cast to the interface
        IAttestationVerifier iface = IAttestationVerifier(address(verifier));
        // Call verify with empty inputs – should return empty bytes (default)
        bytes memory result = iface.verify("", "");
        assertEq(result.length, 0);
    }

    function test_setAndGetUserData() public {
        bytes memory data = abi.encode(uint256(1), uint256(100), bytes32(0), address(0xBEEF), bytes32(0), uint64(60));
        verifier.setUserData(data);

        bytes memory returned = verifier.verify("attestation", "sig");
        assertEq(keccak256(returned), keccak256(data));
    }

    function test_updateUserData() public {
        bytes memory data1 = abi.encode(uint256(1));
        verifier.setUserData(data1);
        assertEq(keccak256(verifier.verify("", "")), keccak256(data1));

        bytes memory data2 = abi.encode(uint256(2));
        verifier.setUserData(data2);
        assertEq(keccak256(verifier.verify("", "")), keccak256(data2));
    }

    function test_verifyIgnoresInputs() public {
        bytes memory data = abi.encode(uint256(42));
        verifier.setUserData(data);

        // Different inputs, same output
        bytes memory r1 = verifier.verify("a", "b");
        bytes memory r2 = verifier.verify("c", "d");
        assertEq(keccak256(r1), keccak256(r2));
    }

    function test_defaultReturnsEmpty() public view {
        bytes memory result = verifier.verify("anything", "anything");
        assertEq(result.length, 0);
    }
}
