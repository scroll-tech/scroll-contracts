// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {IZkEvmVerifierV1, IZkEvmVerifierV2} from "../../libraries/verifier/IZkEvmVerifier.sol";

contract MockZkEvmVerifier is IZkEvmVerifierV1, IZkEvmVerifierV2 {
    event Called(address);

    /// @inheritdoc IZkEvmVerifierV1
    function verify(bytes calldata, bytes32) external view {
        revert(string(abi.encode(address(this))));
    }

    /// @inheritdoc IZkEvmVerifierV2
    function verify(bytes calldata, bytes calldata) external view {
        revert(string(abi.encode(address(this))));
    }
}
