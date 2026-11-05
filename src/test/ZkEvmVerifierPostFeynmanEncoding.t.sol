// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

import {ZkEvmVerifierPostFeynmanLegacy} from "./legacy/ZkEvmVerifierPostFeynmanLegacy.sol";
import {ZkEvmVerifierPostFeynman} from "../libraries/verifier/ZkEvmVerifierPostFeynman.sol";
// Vendored verbatim from scroll-tech/zkvm-prover@bf88715 releases/dev/verifier/verifier.sol
// (identical to openvm-solidity-sdk src/v2.0-base); only the pragma is relaxed. Its
// `Halo2Verifier` base is a stub that accepts every payload.
import {OpenVmHalo2Verifier} from "./openvm/OpenVmHalo2Verifier.sol";

/// Differential test: the payload that reaches the Halo2 fallback must be byte-identical
/// whether it is built by the old raw path (`ZkEvmVerifierPostFeynmanLegacy`) or by the OpenVM
/// wrapper's `_constructProof` behind the typed call (`ZkEvmVerifierPostFeynman`).
contract ZkEvmVerifierPostFeynmanEncodingTest is Test {
    uint256 internal constant BN254_SCALAR_MODULUS = 0x30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001;
    uint256 internal constant ACCUMULATOR_WORDS = 12;
    uint256 internal constant SUFFIX_WORDS = 43;

    OpenVmHalo2Verifier internal wrapper;

    function setUp() public {
        wrapper = new OpenVmHalo2Verifier();
    }

    function testFuzz_oldAndTypedPayloadsMatch(
        bytes32 seed,
        bytes calldata publicInput,
        uint256 digest1,
        uint256 digest2,
        uint256 protocolVersion
    ) external {
        // The wrapper rejects commitments outside the scalar field; the live digests are inside.
        bytes32 d1 = bytes32(bound(digest1, 0, BN254_SCALAR_MODULUS - 1));
        bytes32 d2 = bytes32(bound(digest2, 0, BN254_SCALAR_MODULUS - 1));
        bytes memory bundleProof = _bundleProof(seed);

        ZkEvmVerifierPostFeynmanLegacy oldVerifier = new ZkEvmVerifierPostFeynmanLegacy(
            address(wrapper),
            d1,
            d2,
            protocolVersion
        );
        ZkEvmVerifierPostFeynman newVerifier = new ZkEvmVerifierPostFeynman(address(wrapper), d1, d2, protocolVersion);

        // Old path: the raw staticcall from the verifier into the wrapper's fallback.
        vm.startStateDiffRecording();
        oldVerifier.verify(bundleProof, publicInput);
        bytes memory oldPayload = _calldataOf(vm.stopAndReturnStateDiff(), address(oldVerifier));

        // New path: the wrapper's self-call into its own fallback.
        vm.startStateDiffRecording();
        newVerifier.verify(bundleProof, publicInput);
        bytes memory newPayload = _calldataOf(vm.stopAndReturnStateDiff(), address(wrapper));

        assertEq(oldPayload.length, (ACCUMULATOR_WORDS + 2 + 32 + SUFFIX_WORDS) * 32);
        assertEq(newPayload, oldPayload);
    }

    /// The single call from `accessor` into the wrapper, which must be a successful staticcall.
    function _calldataOf(VmSafe.AccountAccess[] memory accesses, address accessor)
        internal
        view
        returns (bytes memory)
    {
        bytes memory data;
        uint256 found;
        for (uint256 i = 0; i < accesses.length; i++) {
            VmSafe.AccountAccess memory a = accesses[i];
            if (a.account != address(wrapper) || a.accessor != accessor) continue;
            assertEq(uint256(a.kind), uint256(VmSafe.AccountAccessKind.StaticCall));
            assertFalse(a.reverted);
            data = a.data;
            found++;
        }
        assertEq(found, 1);
        return data;
    }

    /// A 1760-byte bundle proof. Every word is random except that the first accumulator
    /// word has its top 4 bytes cleared: a valid proof always has this (88-bit limbs), and
    /// it is what makes the old raw call reach the fallback.
    function _bundleProof(bytes32 seed) internal pure returns (bytes memory proof) {
        uint256 words = ACCUMULATOR_WORDS + SUFFIX_WORDS;
        proof = new bytes(words * 32);
        for (uint256 i = 0; i < words; i++) {
            uint256 word = uint256(keccak256(abi.encode(seed, i)));
            if (i == 0) word >>= 32;
            assembly {
                mstore(add(add(proof, 0x20), mul(i, 0x20)), word)
            }
        }
    }
}
