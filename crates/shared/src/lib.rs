//! Shared types for the autoresearch-fun monorepo.
//!
//! This crate is `no_std`-compatible. Enable the `std` feature (on by default)
//! for standard-library support.

#![cfg_attr(not(feature = "std"), no_std)]

extern crate alloc;

use alloy_sol_types::sol;

// ---------------------------------------------------------------------------
// ABI types – must match the BenchmarkMarket.sol userData layout exactly:
//   (uint256 benchmarkId, uint256 score, bytes32 commitCid,
//    address agent, bytes32 nonce, uint64 elapsedSeconds)
// ---------------------------------------------------------------------------

sol! {
    /// Attestation user-data payload decoded by `BenchmarkMarket.submitImprovement`.
    #[derive(Debug, PartialEq, Eq)]
    struct UserData {
        uint256 benchmarkId;
        uint256 score;
        bytes32 commitCid;
        address agent;
        bytes32 nonce;
        uint64 elapsedSeconds;
    }
}

// ---------------------------------------------------------------------------
// Score constants
// ---------------------------------------------------------------------------

/// Minimum representable score.
pub const MIN_SCORE: u64 = 0;

/// Maximum representable score (1 000 000).
pub const MAX_SCORE: u64 = 1_000_000;

/// Precision denominator used when normalising scores.
pub const SCORE_PRECISION: u64 = 1_000;

// ---------------------------------------------------------------------------
// Benchmark configuration
// ---------------------------------------------------------------------------

/// Static configuration for a benchmark run inside an enclave.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BenchmarkConfig {
    /// Expected PCR0 measurement of the enclave image.
    pub pcr0: [u8; 32],
    /// Maximum wall-clock seconds the benchmark is allowed to run.
    pub max_elapsed_seconds: u64,
}

// ---------------------------------------------------------------------------
// MPP voucher
// ---------------------------------------------------------------------------

/// A voucher representing a micro-payment-protocol claim.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MppVoucher {
    /// Benchmark the voucher is associated with.
    pub benchmark_id: u64,
    /// Agent address (20-byte Ethereum address).
    pub agent: [u8; 20],
    /// USDC amount (6-decimal fixed-point).
    pub amount: u64,
    /// Unique nonce preventing replay.
    pub nonce: [u8; 32],
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Shared error type used across crates.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    /// The supplied score is outside the valid range.
    #[error("invalid score: {0}")]
    InvalidScore(u64),

    /// No benchmark exists with the given id.
    #[error("benchmark not found: {0}")]
    BenchmarkNotFound(u64),

    /// The nonce has already been consumed.
    #[error("nonce already used")]
    NonceAlreadyUsed,

    /// The submitted score does not beat the current best.
    #[error("score not improved")]
    ScoreNotImproved,

    /// The PCR0 measurement does not match any registered oracle.
    #[error("invalid PCR0")]
    InvalidPcr0,

    /// The operation's deadline has already elapsed.
    #[error("deadline passed")]
    DeadlinePassed,
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn score_constants_consistent() {
        assert!(MIN_SCORE < MAX_SCORE);
        assert!(SCORE_PRECISION > 0);
        assert_eq!(MAX_SCORE % SCORE_PRECISION, 0);
    }

    #[test]
    fn benchmark_config_clone_eq() {
        let cfg = BenchmarkConfig {
            pcr0: [0xAA; 32],
            max_elapsed_seconds: 300,
        };
        assert_eq!(cfg, cfg.clone());
    }

    #[test]
    fn mpp_voucher_clone_eq() {
        let v = MppVoucher {
            benchmark_id: 1,
            agent: [0xBB; 20],
            amount: 500_000,
            nonce: [0xCC; 32],
        };
        assert_eq!(v, v.clone());
    }

    #[test]
    fn error_display() {
        let e = Error::InvalidScore(999_999_999);
        let msg = alloc::format!("{e}");
        assert!(msg.contains("999999999"));
    }
}
