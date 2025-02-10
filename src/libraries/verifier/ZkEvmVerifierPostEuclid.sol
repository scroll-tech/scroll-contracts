// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IZkEvmVerifierV2} from "./IZkEvmVerifier.sol";

// solhint-disable no-inline-assembly

contract ZkEvmVerifierPostEuclid is IZkEvmVerifierV2 {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when bundle recursion zk proof verification is failed.
    error VerificationFailed();

    /*************
     * Constants *
     *************/

    /// @notice The address of highly optimized plonk verifier contract.
    address public immutable plonkVerifier;

    /// @notice A predetermined digest for the `plonkVerifier`.
    bytes32 public immutable verifierDigest1;

    /// @notice A predetermined digest for the `plonkVerifier`.
    bytes32 public immutable verifierDigest2;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _verifier,
        bytes32 _verifierDigest1,
        bytes32 _verifierDigest2
    ) {
        plonkVerifier = _verifier;
        verifierDigest1 = _verifierDigest1;
        verifierDigest2 = _verifierDigest2;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IZkEvmVerifierV2
    ///
    /// @dev Encoding for `publicInput`. And this is exactly the same as `ZkEvmVerifierV2`.
    /// ```text
    /// | layer2ChainId | numBatches | prevStateRoot | prevBatchHash | postStateRoot | batchHash | withdrawRoot |
    /// |    8 bytes    |  4  bytes  |   32  bytes   |   32  bytes   |   32  bytes   | 32  bytes |   32 bytes   |
    /// ```
    function verify(bytes calldata bundleProof, bytes calldata publicInput) external view override {
        address _verifier = plonkVerifier;
        bytes32 _verifierDigest1 = verifierDigest1;
        bytes32 _verifierDigest2 = verifierDigest2;
        bytes32 publicInputHash = keccak256(publicInput);
        bool success;

        // 1. the first 12 * 32 (0x180) bytes of `bundleProof` is `accumulator`
        // 2. the rest bytes of `bundleProof` is the actual `bundle_proof`
        // 3. Inserted between `accumulator` and `bundle_proof` are
        //    32 * 34 (0x440) bytes, such that:
        //    | start         | end           | field                   |
        //    |---------------|---------------|-------------------------|
        //    | 0x00          | 0x180         | bundleProof[0x00:0x180] |
        //    | 0x180         | 0x180 + 0x20  | verifierDigest1         |
        //    | 0x180 + 0x20  | 0x180 + 0x40  | verifierDigest2         |
        //    | 0x180 + 0x40  | 0x180 + 0x60  | publicInputHash[0]      |
        //    | 0x180 + 0x60  | 0x180 + 0x80  | publicInputHash[1]      |
        //    ...
        //    | 0x180 + 0x420 | 0x180 + 0x440 | publicInputHash[31]     |
        //    | 0x180 + 0x440 | dynamic       | bundleProof[0x180:]     |
        assembly {
            let p := mload(0x40)
            // 1. copy the accumulator's 0x180 bytes
            calldatacopy(p, bundleProof.offset, 0x180)
            // 2. insert the public input's 0x440 bytes
            mstore(add(p, 0x180), _verifierDigest1) // verifierDigest1
            mstore(add(p, 0x1a0), _verifierDigest2) // verifierDigest2
            for {
                let i := 0
            } lt(i, 0x400) {
                i := add(i, 0x20)
            } {
                mstore(add(p, sub(0x5a0, i)), and(publicInputHash, 0xff))
                publicInputHash := shr(8, publicInputHash)
            }
            // 3. copy all remaining bytes from bundleProof
            calldatacopy(add(p, 0x5c0), add(bundleProof.offset, 0x180), sub(bundleProof.length, 0x180))
            // 4. call plonk verifier
            success := staticcall(gas(), _verifier, p, add(bundleProof.length, 0x440), 0x00, 0x00)
        }
        if (!success) {
            revert VerificationFailed();
        }
    }
}
