// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IZkEvmVerifierV2} from "../libraries/verifier/IZkEvmVerifier.sol";

interface ISGXVerifier is IZkEvmVerifierV2 {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a prover submit a valid attestation report.
    event ProverRegistered(address indexed prover, uint256 validUntil);

    /// @notice Emitted when a prover is selected to prove for next bundle.
    event ProverSelected(address indexed prover, uint256 validUntil);

    /***********
     * Structs *
     ***********/

    /// @dev The struct for report data.
    /// @param addr The address of the prover.
    /// @param referenceBlockNumber The reference block number when the prover generated the report.
    /// @param referenceBlockHash The reference block hash when the prover generated the report.
    struct ReportData {
        address addr;
        uint256 referenceBlockNumber;
        bytes32 referenceBlockHash;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/

    /// @notice Random select a prover.
    function randomSelectNextProver() external returns (address);
}
