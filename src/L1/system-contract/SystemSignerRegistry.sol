// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @dev Example "SystemSignerRegistry" storing `(startBlock, signer)` pairs.
 *      The getSigners() function returns parallel arrays for block numbers and addresses,
 *      
 */
contract SystemSignerRegistry is Ownable {
    struct Signer {
        uint64 startBlock;
        address signer;
    }

    Signer[] private signers;

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    /**
     * @dev Add a (startBlock, signer) pair. Only the owner can do this.
     */
    function addSigner(uint64 _startBlock, address _signer) external onlyOwner {
        require(_signer != address(0), "Zero address not allowed");
        signers.push(Signer({startBlock: _startBlock, signer: _signer}));
    }

    /**
     * @dev Remove a signer by matching both startBlock & signer, or just signer (you choose).
     *      
     */
    function removeSigner(uint64 _startBlock, address _signer) external onlyOwner {
        uint256 length = signers.length;
        for (uint256 i = 0; i < length; i++) {
            // If you only want to match signer, ignore _startBlock
            if (signers[i].startBlock == _startBlock && signers[i].signer == _signer) {
                if (i < length - 1) {
                    signers[i] = signers[length - 1];
                }
                signers.pop();
                return;
            }
        }
        revert("Signer not found");
    }

    /**
     * @dev Return two parallel arrays: blockNumbers and signers.
     *    
     */
    function getSigners() external view returns (uint64[] memory, address[] memory) {
        uint256 len = signers.length;
        uint64[] memory blocks = new uint64[](len);
        address[] memory addrs = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            blocks[i] = signers[i].startBlock;
            addrs[i] = signers[i].signer;
        }
        return (blocks, addrs);
    }
}