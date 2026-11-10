// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {DSTestPlus} from "solmate/test/utils/DSTestPlus.sol";
import {Vm} from "forge-std/Vm.sol";

import {ZkEvmVerifierPostFeynman} from "../libraries/verifier/ZkEvmVerifierPostFeynman.sol";
import {IOpenVmHalo2Verifier} from "../libraries/verifier/IOpenVmHalo2Verifier.sol";

/// @dev Faithful stand-in for the OpenVM 2.0 `OpenVmHalo2Verifier` wrapper. It is
/// `view`, like the real one, and reproduces its external surface: the typed
/// `verify(...)` with selector 0x24270d54, the same length and BN254-modulus checks,
/// and the `proofData[0:4] == 0` assertion. A proof "verifies" only when the tuple
/// (publicValues, proofData, appExeCommit, appVmCommit) equals the one the honest
/// prover produced; this models that the wrapper binds the values it is given, the
/// property Option A' relies on.
contract MockOpenVmWrapper {
    uint256 internal constant BN254_SCALAR_MODULUS = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 internal constant PROOF_DATA_LENGTH = (12 + 43) * 32; // 1760
    uint256 internal constant PUBLIC_VALUES_LENGTH = 32;

    error InvalidPublicValuesLength(uint256 expected, uint256 actual);
    error InvalidProofDataLength(uint256 expected, uint256 actual);
    error InvalidAppExeCommit(bytes32 actual);
    error InvalidAppVmCommit(bytes32 actual);
    error ProofVerificationFailed();

    bytes32 public immutable expExe;
    bytes32 public immutable expVm;
    bytes32 public immutable expPublicValuesHash;
    bytes32 public immutable expProofHash;

    constructor(
        bytes32 _expExe,
        bytes32 _expVm,
        bytes32 _expPublicValuesHash,
        bytes32 _expProofHash
    ) {
        expExe = _expExe;
        expVm = _expVm;
        expPublicValuesHash = _expPublicValuesHash;
        expProofHash = _expProofHash;
    }

    function verify(
        bytes calldata publicValues,
        bytes calldata proofData,
        bytes32 appExeCommit,
        bytes32 appVmCommit
    ) external view {
        if (publicValues.length != PUBLIC_VALUES_LENGTH) {
            revert InvalidPublicValuesLength(PUBLIC_VALUES_LENGTH, publicValues.length);
        }
        if (proofData.length != PROOF_DATA_LENGTH) revert InvalidProofDataLength(PROOF_DATA_LENGTH, proofData.length);
        if (uint256(appExeCommit) >= BN254_SCALAR_MODULUS) revert InvalidAppExeCommit(appExeCommit);
        if (uint256(appVmCommit) >= BN254_SCALAR_MODULUS) revert InvalidAppVmCommit(appVmCommit);
        assert(bytes4(proofData[0:4]) == bytes4(0x00000000));

        bool ok = appExeCommit == expExe &&
            appVmCommit == expVm &&
            keccak256(publicValues) == expPublicValuesHash &&
            keccak256(proofData) == expProofHash;
        if (!ok) revert ProofVerificationFailed();
    }

    fallback() external {}
}

contract ZkEvmVerifierPostFeynmanTest is DSTestPlus {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 internal constant PROOF_DATA_LENGTH = (12 + 43) * 32; // 1760
    uint256 internal constant PROTOCOL_VERSION = 10;

    bytes32 internal constant DIGEST1 = bytes32(uint256(0x1111));
    bytes32 internal constant DIGEST2 = bytes32(uint256(0x2222));

    MockOpenVmWrapper internal wrapper;
    ZkEvmVerifierPostFeynman internal verifier;

    bytes internal honestProof;
    bytes internal honestPublicInput;
    bytes32 internal honestPiHash;

    function setUp() public {
        // A well-formed bundle proof: 1760 bytes, first 4 bytes zero (accumulator limb).
        honestProof = new bytes(PROOF_DATA_LENGTH);
        for (uint256 i = 4; i < PROOF_DATA_LENGTH; i++) honestProof[i] = bytes1(uint8(((i * 7) % 251) + 1));

        honestPublicInput = abi.encodePacked(uint64(534352), keccak256("pi"), uint32(1));
        honestPiHash = keccak256(abi.encodePacked(uint256(PROTOCOL_VERSION), honestPublicInput));

        wrapper = new MockOpenVmWrapper(
            DIGEST1,
            DIGEST2,
            keccak256(abi.encodePacked(honestPiHash)),
            keccak256(honestProof)
        );
        verifier = new ZkEvmVerifierPostFeynman(address(wrapper), DIGEST1, DIGEST2, PROTOCOL_VERSION);
    }

    /// The call must reach the wrapper through selector 0x24270d54, carrying the
    /// public-input hash as `publicValues` and the fixed digests as the commitments.
    /// `bundleProof` is passed as the `proofData` argument, so its bytes can never
    /// become the call selector — the old attack is structurally impossible.
    function test_typedCall_dispatchAndArgs() external {
        bytes memory expectedCalldata = abi.encodeWithSelector(
            IOpenVmHalo2Verifier.verify.selector,
            abi.encodePacked(honestPiHash),
            honestProof,
            DIGEST1,
            DIGEST2
        );
        vm.expectCall(address(wrapper), expectedCalldata);
        verifier.verify(honestProof, honestPublicInput); // must not revert
    }

    /// Public-input binding: the same proof is rejected for a different public input,
    /// because `publicInputHash` (passed as publicValues) no longer matches. This is
    /// the property the vulnerable raw path lost.
    function test_forgedPublicInputRejected() external {
        bytes memory forged = abi.encodePacked(honestPublicInput, uint8(1));
        hevm.expectRevert(ZkEvmVerifierPostFeynman.VerificationFailed.selector);
        verifier.verify(honestProof, forged);
    }

    /// A wrapper-side revert (wrong length, bad commitment, failed proof) surfaces as
    /// VerificationFailed rather than bubbling the raw error.
    function test_wrapperRevertSurfacedAsVerificationFailed() external {
        bytes memory wrongLen = new bytes(PROOF_DATA_LENGTH - 32); // fails the length check
        hevm.expectRevert(ZkEvmVerifierPostFeynman.VerificationFailed.selector);
        verifier.verify(wrongLen, honestPublicInput);
    }

    /// The constructor accepts a digest if and only if it is below the BN254 scalar field modulus.
    function testFuzz_constructorDigestRange(uint256 digest1, uint256 digest2) external {
        uint256 modulus = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
        if (digest1 >= modulus || digest2 >= modulus) {
            hevm.expectRevert(ZkEvmVerifierPostFeynman.InvalidVerifierDigest.selector);
        }
        new ZkEvmVerifierPostFeynman(address(wrapper), bytes32(digest1), bytes32(digest2), PROTOCOL_VERSION);
    }

    function test_constructorDigestBoundary() external {
        uint256 modulus = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
        new ZkEvmVerifierPostFeynman(address(wrapper), bytes32(modulus - 1), bytes32(modulus - 1), PROTOCOL_VERSION);

        hevm.expectRevert(ZkEvmVerifierPostFeynman.InvalidVerifierDigest.selector);
        new ZkEvmVerifierPostFeynman(address(wrapper), bytes32(modulus), DIGEST2, PROTOCOL_VERSION);

        hevm.expectRevert(ZkEvmVerifierPostFeynman.InvalidVerifierDigest.selector);
        new ZkEvmVerifierPostFeynman(address(wrapper), DIGEST1, bytes32(modulus), PROTOCOL_VERSION);
    }

    /// The constructor rejects a plonk verifier without code, including the zero address.
    function test_constructorRejectsVerifierWithoutCode() external {
        hevm.expectRevert(ZkEvmVerifierPostFeynman.InvalidPlonkVerifier.selector);
        new ZkEvmVerifierPostFeynman(address(0), DIGEST1, DIGEST2, PROTOCOL_VERSION);

        hevm.expectRevert(ZkEvmVerifierPostFeynman.InvalidPlonkVerifier.selector);
        new ZkEvmVerifierPostFeynman(address(0xBEEF), DIGEST1, DIGEST2, PROTOCOL_VERSION);
    }
}
