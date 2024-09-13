// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ============ Internal Imports ============

// ============ External Imports ============
import { AbstractRoutingIsm } from "@hyperlane-xyz/isms/routing/AbstractRoutingIsm.sol";
import { IMailbox } from "@hyperlane-xyz/interfaces/IMailbox.sol";
import { IInterchainSecurityModule } from "@hyperlane-xyz/interfaces/IInterchainSecurityModule.sol";
import { Message } from "@hyperlane-xyz/libs/Message.sol";
import { InterchainCreate2FactoryMessage } from "./libs/InterchainCreate2FactoryMessage.sol";

/**
 * @title InterchainCreate2FactoryIsm
 */
contract InterchainCreate2FactoryIsm is AbstractRoutingIsm {
    IMailbox private immutable mailbox;

    // ============ Constructor ============
    constructor(address _mailbox) {
        mailbox = IMailbox(_mailbox);
    }

    // ============ Public Functions ============

    /**
     * @notice Returns the ISM responsible for verifying _message
     * @param _message Formatted Hyperlane message (see Message.sol).
     * @return module The ISM to use to verify _message
     */
    function route(bytes calldata _message) public view virtual override returns (IInterchainSecurityModule) {
        address _ism = InterchainCreate2FactoryMessage.ism(Message.body(_message));
        if (_ism == address(0)) {
            return IInterchainSecurityModule(address(mailbox.defaultIsm()));
        } else {
            return IInterchainSecurityModule(_ism);
        }
    }
}
