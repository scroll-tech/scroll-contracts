// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IZkEvmVerifierV2} from "./IZkEvmVerifier.sol";

// solhint-disable no-inline-assembly

contract ZkEvmVerifierV2 is IZkEvmVerifierV2 {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when aggregate zk proof verification is failed.
    error VerificationFailed();

    /*************
     * Constants *
     *************/

    /// @notice The address of highly optimized plonk verifier contract.
    address public immutable plonkVerifier;

    /***************
     * Constructor *
     ***************/

    constructor(address _verifier) {
        plonkVerifier = _verifier;
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @inheritdoc IZkEvmVerifierV2
    /// @dev Encoding for `publicInput`
    /// ```text
    /// | layer2ChainId | prevStateRoot | prevBatchHash | postStateRoot | withdrawRoot | batchHash |
    /// |    8 bytes    |   32  bytes   |   32  bytes   |   32  bytes   |   32 bytes   | 32  bytes |
    /// ```
    function verify(bytes calldata aggrProof, bytes calldata publicInput) external view override {
        address _verifier = plonkVerifier;
        bool success;

        // 1. the first 12 * 32 (0x180) bytes of `aggrProof` is `accumulator`
        // 2. the rest bytes of `aggrProof` is the actual `batch_aggregated_proof`
        // 3. Inserted between `accumulator` and `batch_aggregated_proof` are
        //    32 * 11 (0x160) bytes, such that:
        //    | start         | end           | field                 |
        //    |---------------|---------------|-----------------------|
        //    | 0x00          | 0x180         | aggrProof[0x00:0x180] |
        //    | 0x180         | 0x180 + 0x20  | layer2ChainId         |
        //    | 0x180 + 0x20  | 0x180 + 0x40  | prevStateRoot_hi      |
        //    | 0x180 + 0x40  | 0x180 + 0x60  | prevStateRoot_lo      |
        //    | 0x180 + 0x60  | 0x180 + 0x80  | prevBatchHash_hi      |
        //    | 0x180 + 0x80  | 0x180 + 0xa0  | prevBatchHash_lo      |
        //    | 0x180 + 0xa0  | 0x180 + 0xc0  | postStateRoot_hi      |
        //    | 0x180 + 0xc0  | 0x180 + 0xe0  | postStateRoot_lo      |
        //    | 0x180 + 0xe0  | 0x180 + 0x100 | withdrawRoot_hi       |
        //    | 0x180 + 0x100 | 0x180 + 0x120 | withdrawRoot_lo       |
        //    | 0x180 + 0x120 | 0x180 + 0x140 | batchHash_hi          |
        //    | 0x180 + 0x140 | 0x180 + 0x160 | batchHash_lo          |
        //    | 0x180 + 0x160 | dynamic       | aggrProof[0x180:]     |
        assembly {
            let p := mload(0x40)
            // 1. copy the accumulator's 0x180 bytes
            calldatacopy(p, aggrProof.offset, 0x180)
            // 2. insert the public input's 0x160 bytes
            mstore(add(p, 0x180), shr(192, calldataload(publicInput.offset))) // layer2ChainId
            let prevStateRoot := calldataload(add(publicInput.offset, 0x08))
            mstore(add(p, 0x1a0), shr(128, prevStateRoot))
            mstore(add(p, 0x1c0), and(prevStateRoot, 0xffffffffffffffffffffffffffffffff))
            let prevBatchHash := calldataload(add(publicInput.offset, 0x28))
            mstore(add(p, 0x1e0), shr(128, prevBatchHash))
            mstore(add(p, 0x200), and(prevBatchHash, 0xffffffffffffffffffffffffffffffff))
            let postStateRoot := calldataload(add(publicInput.offset, 0x48))
            mstore(add(p, 0x220), shr(128, postStateRoot))
            mstore(add(p, 0x240), and(postStateRoot, 0xffffffffffffffffffffffffffffffff))
            let withdrawRoot := calldataload(add(publicInput.offset, 0x68))
            mstore(add(p, 0x260), shr(128, withdrawRoot))
            mstore(add(p, 0x280), and(withdrawRoot, 0xffffffffffffffffffffffffffffffff))
            let batchHash := calldataload(add(publicInput.offset, 0x88))
            mstore(add(p, 0x2a0), shr(128, batchHash))
            mstore(add(p, 0x2c0), and(batchHash, 0xffffffffffffffffffffffffffffffff))
            // 3. copy all remaining bytes from aggrProof
            calldatacopy(add(p, 0x2e0), add(aggrProof.offset, 0x180), sub(aggrProof.length, 0x180))

            // 4. call plonk verifier
            success := staticcall(gas(), _verifier, p, add(aggrProof.length, 0x160), 0x00, 0x00)
        }
        if (!success) {
            revert VerificationFailed();
        }
    }
}
