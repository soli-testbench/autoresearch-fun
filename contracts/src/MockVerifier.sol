// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAttestationVerifier} from "./IAttestationVerifier.sol";

/// @title MockVerifier
/// @notice Test-only implementation of IAttestationVerifier that returns caller-controlled userData.
/// @dev ⚠️  SECURITY: This contract is for LOCAL TESTING ONLY. It performs NO cryptographic
///      verification — any caller can set arbitrary userData via `setUserData`. Deploying this
///      contract as the verifier in a production `BenchmarkMarket` would allow anyone to forge
///      attestations and drain all threshold stakes.
///
///      Production deployments MUST use a verifier that:
///        1. Validates the attestation signature against a trusted root (e.g. AWS Nitro root cert).
///        2. Returns only the userData embedded in the cryptographically verified attestation.
///        3. Ensures the PCR0 value in userData matches the enclave measurement from the attestation.
contract MockVerifier is IAttestationVerifier {
    bytes private _userData;

    /// @notice Set the userData that will be returned by `verify`.
    /// @dev Only exists for testing. A production verifier would never expose this.
    function setUserData(bytes calldata userData_) external {
        _userData = userData_;
    }

    /// @inheritdoc IAttestationVerifier
    function verify(bytes calldata, bytes calldata)
        external
        view
        override
        returns (bytes memory)
    {
        return _userData;
    }
}
