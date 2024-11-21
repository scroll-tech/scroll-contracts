// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

contract MockDcapAttestation {
    bool public success;
    bytes public output;

    function setValue(bool _success, bytes memory _output) external {
        success = _success;
        output = _output;
    }

    function verifyAndAttestOnChain(bytes calldata) external view returns (bool, bytes memory) {
        return (success, output);
    }
}
