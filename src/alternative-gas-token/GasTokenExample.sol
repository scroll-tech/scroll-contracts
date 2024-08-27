// SPDX-License-Identifier: MIT

pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";

contract GasTokenExample is ERC20 {
    uint8 private decimals_;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _recipient,
        uint256 _amount
    ) ERC20(_name, _symbol) {
        decimals_ = _decimals;
        _mint(_recipient, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return decimals_;
    }
}
