// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// solhint-disable no-empty-blocks

/// @dev Test stub for the `snark-verifier` output. It accepts every payload, so the
/// vendored `OpenVmHalo2Verifier` wrapper runs unchanged and its self-call calldata
/// can be recorded. The wrapper ignores the fallback's return data.
contract Halo2Verifier {
    fallback() external {}
}
