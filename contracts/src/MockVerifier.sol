// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAttestationVerifier} from "./IAttestationVerifier.sol";

/// @title MockVerifier
/// @notice Test-only implementation of IAttestationVerifier that returns caller-controlled userData.
contract MockVerifier is IAttestationVerifier {
    bytes private _userData;

    /// @notice Set the userData that will be returned by `verify`.
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
