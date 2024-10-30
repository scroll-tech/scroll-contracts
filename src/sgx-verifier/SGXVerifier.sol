// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {IAttestationVerifier} from "./IAttestationVerifier.sol";
import {ISGXVerifier, IZkEvmVerifierV2} from "./ISGXVerifier.sol";

/// @dev This contract is modified from https://github.com/automata-network/scroll-prover/blob/demo/contracts/src/core/ProverRegistry.sol
contract SGXVerifier is AccessControlEnumerable, EIP712, ISGXVerifier {
    /**********
     * Errors *
     **********/

    /// @dev Thrown when the given block number is invalid.
    error ErrorInvalidBlockNumber();

    /// @dev Thrown when the given block number is outdated.
    error ErrorBlockNumberOutOfDate();

    /// @dev Thrown when the given block hash mismatch.
    error ErrorBlockHashMismatch();

    /// @dev Thrown when the given attestation report is used before.
    error ErrorReportUsed();

    /// @dev Thrown when the prover's attestation report expired.
    error ErrorProverOutOfDate();

    /*************
     * Constants *
     *************/

    /// @dev The role for prover registration.
    bytes32 PROVER_REGISTER_ROLE = keccak256("PROVER_REGISTER_ROLE");

    /// @dev type hash for struct `ProveBundleSignatureData`.
    bytes32 private constant _BUNDLE_PAYLOAD_TYPEHASH =
        keccak256(
            "ProveBundleSignatureData(uint64 layer2ChainId,uint32 numBatches,bytes32 prevStateRoot,bytes32 prevBatchHash,bytes32 postStateRoot,bytes32 batchHash,bytes32 postWithdrawRoot)"
        );

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of `AttestationVerifier` contract.
    address public immutable attestationVerifier;

    /// @notice The number of seconds of the attestation validity.
    uint256 public immutable attestValiditySeconds;

    /// @notice The maximum number of blocks allowed for the attestation report.
    uint256 public immutable maxBlockNumberDiff;

    /*********************
     * Storage Variables *
     *********************/

    /// @notice The list of attested reports, mapping from report hash to attested status.
    mapping(bytes32 => bool) public attestedReports;

    /// @notice The list of attested provers, mapping from prover address to `ProverInstance`.
    mapping(address => ProverInstance) public attestedProvers;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _attestationVerifier,
        uint256 _attestValiditySeconds,
        uint256 _maxBlockNumberDiff
    ) EIP712("SGXVerifier", "1") {
        attestationVerifier = _attestationVerifier;
        attestValiditySeconds = _attestValiditySeconds;
        maxBlockNumberDiff = _maxBlockNumberDiff;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Return the EIP712 hash for `ProveBundleSignatureData`
    /// @dev The struct is below, also see https://github.com/scroll-tech/sgx-prover/blob/main/crates/rpc/src/types.rs
    /// ```text
    /// struct ProveBundleSignatureData {
    ///     layer2ChainId uint64;
    ///     numBatches uint32;
    ///     prevStateRoot bytes32;
    ///     prevBatchHash bytes32;
    ///     postStateRoot bytes32;
    ///     batchHash bytes32;
    ///     postWithdrawRoot bytes32;
    /// }
    /// ```
    function getProveBundleSignatureDataHash(
        uint64 layer2ChainId,
        uint32 numBatches,
        bytes32 prevStateRoot,
        bytes32 prevBatchHash,
        bytes32 postStateRoot,
        bytes32 batchHash,
        bytes32 postWithdrawRoot
    ) public view returns (bytes32) {
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
        return _hashTypedDataV4(structHash);
    }

    /// @inheritdoc IZkEvmVerifierV2
    ///
    /// @dev Encoding for `publicInput`
    /// ```text
    /// | layer2ChainId | numBatches | prevStateRoot | prevBatchHash | postStateRoot | batchHash | postWithdrawRoot |
    /// |    8 bytes    |  4  bytes  |   32  bytes   |   32  bytes   |   32  bytes   | 32  bytes |     32 bytes     |
    /// ```
    ///
    /// This function will revert when the proof is invalid.
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

        bytes32 hash = getProveBundleSignatureDataHash(
            layer2ChainId,
            numBatches,
            prevStateRoot,
            prevBatchHash,
            postStateRoot,
            batchHash,
            postWithdrawRoot
        );
        address prover = ECDSA.recover(hash, bundleProof);

        if (attestedProvers[prover].validUntil < block.timestamp) {
            revert ErrorProverOutOfDate();
        }
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice register prover instance with quote
    /// @param _report The generated attestation report by the prover.
    /// @param _data The custom data attached with the report.
    function register(bytes calldata _report, ReportData calldata _data) external {
        // @note We disable whitelist when `address(0)` is whitelisted.
        if (!hasRole(PROVER_REGISTER_ROLE, address(0))) {
            _checkRole(PROVER_REGISTER_ROLE, _msgSender());
        }

        // check reference block number is valid
        _checkBlockNumber(_data.referenceBlockNumber, _data.referenceBlockHash);
        bytes32 dataHash = keccak256(abi.encode(_data));

        // verify the report
        IAttestationVerifier(attestationVerifier).verifyAttestation(_report, dataHash);

        bytes32 reportHash = keccak256(_report);
        if (attestedReports[reportHash]) {
            revert ErrorReportUsed();
        }
        attestedReports[reportHash] = true;

        // This won't exceed `type(uint64).max`.
        uint256 validUntil = block.timestamp + attestValiditySeconds;
        attestedProvers[_data.addr] = ProverInstance(_data.addr, uint64(validUntil));

        emit ProverRegistered(_data.addr, validUntil);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// Due to the inherent unpredictability of blockHash, it mitigates the risk of mass-generation
    /// of attestation reports in a short time frame, preventing their delayed and gradual exploitation.
    /// This function will make sure the attestation report generated in recent ${maxBlockNumberDiff} blocks
    function _checkBlockNumber(uint256 blockNumber, bytes32 blockHash) private view {
        if (blockNumber >= block.number) {
            revert ErrorInvalidBlockNumber();
        }
        if (block.number - blockNumber >= maxBlockNumberDiff) {
            revert ErrorBlockNumberOutOfDate();
        }
        if (blockhash(blockNumber) != blockHash) {
            revert ErrorBlockHashMismatch();
        }
    }
}
