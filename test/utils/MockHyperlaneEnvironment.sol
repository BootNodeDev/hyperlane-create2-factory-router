// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@hyperlane-xyz/mock/MockMailbox.sol";
import "@hyperlane-xyz/test/TestInterchainGasPaymaster.sol";
import "@hyperlane-xyz/test/TestIsm.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";

contract MockHyperlaneEnvironment {
    uint32 public originDomain;
    uint32[] public destinationDomains;

    mapping(uint32 => MockMailbox) public mailboxes;
    mapping(uint32 => TestInterchainGasPaymaster) public igps;
    mapping(uint32 => IInterchainSecurityModule) public isms;

    constructor(uint32 _originDomain, uint32[] memory _destinationDomains) {
        originDomain = _originDomain;
        destinationDomains = _destinationDomains;

        MockMailbox originMailbox = new MockMailbox(_originDomain);
        isms[originDomain] = new TestIsm();
        originMailbox.setDefaultIsm(address(isms[originDomain]));
        originMailbox.transferOwnership(msg.sender);
        mailboxes[_originDomain] = originMailbox;

        MockMailbox[] memory destinationsMailbox = new MockMailbox[](_destinationDomains.length);
        for (uint256 i = 0; i < _destinationDomains.length; i++) {
            destinationsMailbox[i] = new MockMailbox(_destinationDomains[i]);

            originMailbox.addRemoteMailbox(_destinationDomains[i], destinationsMailbox[i]);
            destinationsMailbox[i].addRemoteMailbox(_originDomain, originMailbox);
            isms[destinationDomains[i]] = new TestIsm();
            destinationsMailbox[i].setDefaultIsm(address(isms[destinationDomains[i]]));
            destinationsMailbox[i].transferOwnership(msg.sender);
            mailboxes[_destinationDomains[i]] = destinationsMailbox[i];
        }
    }

    function processNextPendingMessage(uint32 _destinationDomain) public {
        mailboxes[_destinationDomain].processNextInboundMessage();
    }

    function processNextPendingMessageFromDestination() public {
        mailboxes[originDomain].processNextInboundMessage();
    }
}
