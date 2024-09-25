// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import {L2TxFeeVault} from "../L2/predeploys/L2TxFeeVault.sol";
import {IL2ETHGateway} from "../L2/gateways/IL2ETHGateway.sol";

contract L2TxFeeVaultWithGasToken is L2TxFeeVault {
    /*************
     * Constants *
     *************/

    /// @notice The address of `L2ETHGateway` contract.
    address public ETHGateway;

    /***************
     * Constructor *
     ***************/

    constructor(
        address _ETHGateway,
        address _owner,
        address _recipient,
        uint256 _minWithdrawalAmount
    ) L2TxFeeVault(_owner, _recipient, _minWithdrawalAmount) {
        ETHGateway = _ETHGateway;
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Update the address of ETHGateway.
    /// @param _newETHGateway The address of ETHGateway to update.
    function updateNativeTokenGateway(address _newETHGateway) external onlyOwner {
        address _oldETHGateway = ETHGateway;
        ETHGateway = _newETHGateway;

        emit UpdateMessenger(_oldETHGateway, _newETHGateway);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @inheritdoc L2TxFeeVault
    function sendWithdrawMessage(address _recipient, uint256 _value) internal override {
        // no fee provided
        IL2ETHGateway(ETHGateway).withdrawETH{value: _value}(
            _recipient,
            _value,
            0 // _gasLimit can be zero for fee vault.
        );
    }
}
