// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IZkEvmVerifierV2} from "../libraries/verifier/IZkEvmVerifier.sol";

interface ISGXVerifier is IZkEvmVerifierV2 {
    event InstanceAdded(address indexed id, uint256 validUntil);

    struct ProverInstance {
        address addr;
        uint256 validUntil;
    }

    struct ReportData {
        address addr;
        uint256 teeType;
        uint256 referenceBlockNumber;
        bytes32 referenceBlockHash;
    }

    /// @notice register prover instance with quote
    function register(bytes calldata _report, ReportData calldata _data) external;
}
