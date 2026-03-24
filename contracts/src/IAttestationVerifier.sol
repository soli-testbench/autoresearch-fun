// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IAttestationVerifier
/// @notice Interface for verifying enclave attestations (e.g. AWS Nitro).
interface IAttestationVerifier {
    /// @notice Verify an attestation and return the embedded userData.
    /// @param attestationTbs The to-be-signed portion of the attestation document.
    /// @param sig            The signature over attestationTbs.
    /// @return userData      ABI-encoded application payload extracted from the attestation.
    function verify(bytes calldata attestationTbs, bytes calldata sig)
        external
        view
        returns (bytes memory userData);
}
