// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract SystemConfig is Ownable {

    address public currentSigner;

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    /**
     * @dev Update the current signer.
     *      Only the owner can call this function.
     * @param _newSigner The address of the new authorized signer.
     */
    function updateSigner(address _newSigner) external onlyOwner {
        currentSigner = _newSigner;
    }

    /**
     * @dev Return the current authorized signer.
     * @return The authorized signer address.
     */
    function getSigner() external view returns (address) {
        return currentSigner;
    }
}