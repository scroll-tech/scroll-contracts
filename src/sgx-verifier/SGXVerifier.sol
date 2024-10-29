// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IAttestationVerifier} from "./IAttestationVerifier.sol";
import {ISGXVerifier, IZkEvmVerifierV2} from "./ISGXVerifier.sol";

contract SGXVerifier is EIP712, ISGXVerifier {
    error INVALID_BLOCK_NUMBER();
    error BLOCK_NUMBER_OUT_OF_DATE();
    error BLOCK_NUMBER_MISMATCH();
    error REPORT_USED();
    error INVALID_PROVER_INSTANCE();
    error PROVER_TYPE_MISMATCH();
    error INVALID_REPORT();
    error INVALID_REPORT_DATA();
    error REPORT_DATA_MISMATCH();
    error PROVER_INVALID_INSTANCE_ID(uint256);
    error PROVER_INVALID_ADDR(address);
    error PROVER_ADDR_MISMATCH(address, address);
    error PROVER_OUT_OF_DATE(uint256);

    bytes32 private constant _BUNDLE_PAYLOAD_TYPEHASH =
        keccak256(
            "ProveBundleSignatureData(uint64 layer2ChainId,uint32 numBatches,bytes32 prevStateRoot,bytes32 prevBatchHash,bytes32 postStateRoot,bytes32 batchHash,bytes32 postWithdrawRoot)"
        );

    address public immutable attestationVerifier;

    uint256 public immutable attestValiditySeconds;

    uint256 public immutable maxBlockNumberDiff;

    mapping(bytes32 => bool) public attestedReports;

    mapping(address => ProverInstance) public attestedProvers;

    constructor(
        address _attestationVerifier,
        uint256 _attestValiditySeconds,
        uint256 _maxBlockNumberDiff
    ) EIP712("SGXVerifier", "1") {
        attestationVerifier = _attestationVerifier;
        attestValiditySeconds = _attestValiditySeconds;
        maxBlockNumberDiff = _maxBlockNumberDiff;
    }

    /// @inheritdoc ISGXVerifier
    function register(bytes calldata _report, ReportData calldata _data) external {
        _checkBlockNumber(_data.referenceBlockNumber, _data.referenceBlockHash);
        bytes32 dataHash = keccak256(abi.encode(_data));

        IAttestationVerifier(attestationVerifier).verifyAttestation(_report, dataHash);

        bytes32 reportHash = keccak256(_report);
        if (attestedReports[reportHash]) revert REPORT_USED();
        attestedReports[reportHash] = true;

        uint256 validUntil = block.timestamp + attestValiditySeconds;
        attestedProvers[_data.addr] = ProverInstance(_data.addr, validUntil);
        emit InstanceAdded(_data.addr, validUntil);
    }

    /// @inheritdoc IZkEvmVerifierV2
    ///
    /// @dev Encoding for `publicInput`
    /// ```text
    /// | layer2ChainId | numBatches | prevStateRoot | prevBatchHash | postStateRoot | batchHash | postWithdrawRoot |
    /// |    8 bytes    |  4  bytes  |   32  bytes   |   32  bytes   |   32  bytes   | 32  bytes |     32 bytes     |
    /// ```
    function verify(bytes calldata bundleProof, bytes calldata publicInput) external view override {
        uint64 layer2ChainId;
        uint32 numBatches;
        bytes32 prevStateRoot;
        bytes32 prevBatchHash;
        bytes32 postStateRoot;
        bytes32 batchHash;
        bytes32 postWithdrawRoot;
        assembly {
            layer2ChainId := shr(192, calldataload(publicInput.offset))
            numBatches := shr(224, calldataload(add(publicInput.offset, 0x08)))
            prevStateRoot := calldataload(add(publicInput.offset, 0xc))
            prevBatchHash := calldataload(add(publicInput.offset, 0x2c))
            postStateRoot := calldataload(add(publicInput.offset, 0x4c))
            batchHash := calldataload(add(publicInput.offset, 0x6c))
            postWithdrawRoot := calldataload(add(publicInput.offset, 0x8c))
        }

        bytes32 structHash = keccak256(
            abi.encode(
                _BUNDLE_PAYLOAD_TYPEHASH,
                layer2ChainId,
                numBatches,
                prevStateRoot,
                prevBatchHash,
                postStateRoot,
                batchHash,
                postWithdrawRoot
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address prover = ECDSA.recover(hash, bundleProof);

        if (attestedProvers[prover].validUntil < block.timestamp) revert();
    }

    // Due to the inherent unpredictability of blockHash, it mitigates the risk of mass-generation
    //   of attestation reports in a short time frame, preventing their delayed and gradual exploitation.
    // This function will make sure the attestation report generated in recent ${maxBlockNumberDiff} blocks
    function _checkBlockNumber(uint256 blockNumber, bytes32 blockHash) private view {
        if (blockNumber >= block.number) revert INVALID_BLOCK_NUMBER();
        if (block.number - blockNumber >= maxBlockNumberDiff) revert BLOCK_NUMBER_OUT_OF_DATE();
        if (blockhash(blockNumber) != blockHash) revert BLOCK_NUMBER_MISMATCH();
    }
}
