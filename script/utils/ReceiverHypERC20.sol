// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { HypERC20 } from "@hyperlane-xyz/token/HypERC20.sol";

contract ReceiverHypERC20 is HypERC20 {
    constructor(uint8 __decimals, address _mailbox) HypERC20(__decimals, _mailbox) { }

    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner,
        address _receiver
    )
        external
        initializer
    {
        // Initialize ERC20 metadata
        __ERC20_init(_name, _symbol);
        _mint(_receiver, _totalSupply);
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
    }
}
