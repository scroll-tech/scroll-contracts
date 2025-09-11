// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IL2ERC20Gateway} from "../L2/gateways/IL2ERC20Gateway.sol";

interface IL2ERC20GatewayValidium is IL2ERC20Gateway {
    /// @notice Complete a deposit from L1 to L2 and send fund to recipient's account in L2.
    /// @dev Make this function payable to handle WETH deposit/withdraw.
    ///      The function should only be called by L2ScrollMessenger.
    ///      The function should also only be called by L1ERC20Gateway in L1.
    /// @dev This function is not implemented. Instead, it is used to signal to the sequencer
    //       that the target address is encrypted. The sequencer should then decrypt the address
    //       and call the standard `finalizeDepositERC20` function with the decrypted address.
    /// @param l1Token The address of corresponding L1 token.
    /// @param l2Token The address of corresponding L2 token.
    /// @param from The address of account who deposits the token in L1.
    /// @param to The encrypted address of recipient in L2 to receive the token.
    /// @param amount The amount of the token to deposit.
    /// @param data Optional data to forward to recipient's account.
    function finalizeDepositERC20Encrypted(
        address l1Token,
        address l2Token,
        address from,
        bytes memory to,
        uint256 amount,
        bytes calldata data
    ) external payable;
}
