// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ============ Internal Imports ============
import { InterchainCreate2FactoryMessage } from "./libs/InterchainCreate2FactoryMessage.sol";

// ============ External Imports ============
import { IPostDispatchHook } from "@hyperlane-xyz/interfaces/hooks/IPostDispatchHook.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { Router } from "@hyperlane-xyz/client/Router.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

/*
 * @title A contract that allows accounts on chain A to deploy contracts on chain B.
 */
contract InterchainCreate2FactoryRouter is Router {
    // ============ Libraries ============

    using TypeCasts for address;
    using TypeCasts for bytes32;

    // ============ Constants ============

    // ============ Public Storage ============

    // ============ Upgrade Gap ============

    uint256[47] private __GAP;

    // ============ Events ============

    event RemoteDeployDispatched(
        uint32 indexed destination, bytes32 indexed router, address indexed owner, uint32 _destination, bytes32 ism
    );

    event Deployed(bytes32 indexed bytecodeHash, bytes32 indexed salt, address indexed deployedAddress);

    // ============ Constructor ============

    constructor(address _mailbox) Router(_mailbox) { }

    // ============ Initializers ============

    /**
     * @notice Initializes the contract with HyperlaneConnectionClient contracts
     * @param _domains The domains of the remote Application Routers
     * @param _customHook used by the Router to set the hook to override with
     * @param _interchainSecurityModule The address of the local ISM contract
     * @param _owner The address with owner privileges
     */
    function initialize(
        uint32[] calldata _domains,
        address _customHook,
        address _interchainSecurityModule,
        address _owner
    )
        external
        initializer
    {
        _MailboxClient_initialize(_customHook, _interchainSecurityModule, _owner);

        uint256 length = _domains.length;
        for (uint256 i = 0; i < length; i += 1) {
            _enrollRemoteRouter(_domains[i], TypeCasts.addressToBytes32(address(this)));
        }
    }

    // ============ External Functions ============

    /**
     * @notice Register the address of a Router contract with the same address as this for the same Application on a
     * remote chain
     * @param _domain The domain of the remote Application Router
     */
    function enrollRemoteDomain(uint32 _domain) external virtual onlyOwner {
        _enrollRemoteRouter(_domain, TypeCasts.addressToBytes32(address(this)));
    }

    /**
     * @notice Batch version of `enrollRemoteDomain
     * @param _domains The domains of the remote Application Routers
     */
    function enrollRemoteDomains(uint32[] calldata _domains) external virtual onlyOwner {
        uint256 length = _domains.length;
        for (uint256 i = 0; i < length; i += 1) {
            _enrollRemoteRouter(_domains[i], TypeCasts.addressToBytes32(address(this)));
        }
    }

    /**
     * @notice Deploys a contract on the `_destination` chain
     * @param _destination The remote domain
     * @param _ism The address of the remote ISM, zero address for using the remote mailbox default ISM
     * @param _salt The salt used for deploying the contract with CREATE2
     * @param _bytecode The bytecode of the contract to deploy
     * @param _initCode The initialization that is called after the contract is deployed, empty for no initialization
     */
    function deployContract(
        uint32 _destination,
        bytes32 _ism,
        bytes32 _salt,
        bytes memory _bytecode,
        bytes memory _initCode
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = _mustHaveRemoteRouter(_destination);

        return deployContractWithOverrides(_destination, _router, _ism, _salt, address(hook), _bytecode, _initCode);
    }

    /**
     * @notice Deploys a contract on the `_destination` chain with hook metadata
     * @param _destination The remote domain
     * @param _ism The address of the remote ISM, zero address for using the remote mailbox default ISM
     * @param _salt The salt used for deploying the contract with CREATE2
     * @param _bytecode The bytecode of the contract to deploy
     * @param _initCode The initialization that is called after the contract is deployed, empty for no initialization
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function deployContract(
        uint32 _destination,
        bytes32 _ism,
        bytes32 _salt,
        bytes memory _bytecode,
        bytes memory _initCode,
        bytes memory _hookMetadata
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = _mustHaveRemoteRouter(_destination);

        return deployContractWithOverrides(
            _destination, _router, _ism, _salt, address(hook), _bytecode, _initCode, _hookMetadata
        );
    }

    /**
     * @notice Handles dispatched messages by deploying the contract using the data from an incoming message
     * @param _message The message containing the data sent by the remote router
     * @dev Does not need to be onlyRemoteRouter, as this application is designed
     * to receive messages from untrusted remote contracts.
     */
    function handle(uint32, bytes32, bytes calldata _message) external payable override onlyMailbox {
        (bytes32 _sender,, bytes32 _salt, bytes memory _bytecode, bytes memory _initCode) =
            InterchainCreate2FactoryMessage.decode(_message);

        address deployedAddress_ = _deploy(_bytecode, _getSalt(_sender, _salt));

        if (_initCode.length > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = deployedAddress_.call(_initCode);
            require(success, "failed to init");
        }
    }

    /**
     * @notice Returns the gas payment required to dispatch a given messageBody to the given domain's router with gas
     * limit override.
     * @param _destination The domain of the destination router.
     * @param _messageBody The message body to be dispatched.
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function quoteGasPayment(
        uint32 _destination,
        bytes memory _messageBody,
        bytes memory _hookMetadata
    )
        external
        view
        returns (uint256 _gasPayment)
    {
        return _Router_quoteDispatch(_destination, _messageBody, _hookMetadata, address(hook));
    }

    /**
     * @notice Returns the gas payment required to dispatch a given messageBody to the given domain's router with gas
     * limit override.
     * @param _destination The domain of the destination router.
     * @param _router The destination router.
     * @param _hook The a hook to override the default hook.
     * @param _messageBody The message body to be dispatched.
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function quoteGasPaymentWithOverrides(
        uint32 _destination,
        bytes32 _router,
        address _hook,
        bytes memory _messageBody,
        bytes memory _hookMetadata
    )
        external
        view
        returns (uint256 _gasPayment)
    {
        return mailbox.quoteDispatch(_destination, _router, _messageBody, _hookMetadata, IPostDispatchHook(_hook));
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} or {deployAndInit} by `sender`.
     * Any change in the `bytecode`, `sender`, or `salt` will result in a new destination address.
     */
    function deployedAddress(address _sender, bytes32 _salt, bytes memory _bytecode) external view returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            address(this),
                            _getSalt(TypeCasts.addressToBytes32(_sender), _salt),
                            keccak256(_bytecode) // init code hash
                        )
                    )
                )
            )
        );
    }

    // ============ Public Functions ============

    /**
     * @notice Deploys and initialize a contract on the `_destination` chain with hook metadata
     * @param _destination The remote domain
     * @param _router The remote router address
     * @param _ism The address of the remote ISM, zero address for using the remote mailbox default ISM
     * @param _salt The salt used for deploying the contract with CREATE2
     * @param _hook The address hook to override the default hook
     * @param _bytecode The bytecode of the contract to deploy
     * @param _initCode The initialization that is called after the contract is deployed
     */
    function deployContractWithOverrides(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes32 _salt,
        address _hook,
        bytes memory _bytecode,
        bytes memory _initCode
    )
        public
        payable
        returns (bytes32)
    {
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, _initCode);

        return _dispatchMessage(_destination, _router, _ism, _hook, _body, new bytes(0));
    }

    /**
     * @notice Deploys and initialize a contract on the `_destination` chain with hook metadata
     * @param _destination The remote domain
     * @param _router The remote router address
     * @param _ism The address of the remote ISM, zero address for using the remote mailbox default ISM
     * @param _salt The salt used for deploying the contract with CREATE2
     * @param _hook The address hook to override the default hook
     * @param _bytecode The bytecode of the contract to deploy
     * @param _initCode The initialization that is called after the contract is deployed
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function deployContractWithOverrides(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes32 _salt,
        address _hook,
        bytes memory _bytecode,
        bytes memory _initCode,
        bytes memory _hookMetadata
    )
        public
        payable
        returns (bytes32)
    {
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, _initCode);

        return _dispatchMessage(_destination, _router, _ism, _hook, _body, _hookMetadata);
    }

    // ============ Internal Functions ============

    /**
     * @dev Required for use of Router, compiler will not include this function in the bytecode
     */
    function _handle(uint32, bytes32, bytes calldata) internal pure override {
        assert(false);
    }

    /**
     * @notice Dispatches an InterchainCreate2FactoryMessage to the remote router
     * @param _destination The remote domain
     * @param _router The remote origin InterchainCreate2FactoryRouter
     * @param _ism The address of the remote ISM
     * @param _hook The address hook
     * @param _messageBody The InterchainCreate2FactoryMessage body
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function _dispatchMessage(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        address _hook,
        bytes memory _messageBody,
        bytes memory _hookMetadata
    )
        private
        returns (bytes32)
    {
        emit RemoteDeployDispatched(_destination, _router, msg.sender, _destination, _ism);

        return mailbox.dispatch{ value: msg.value }(
            _destination, _router, _messageBody, _hookMetadata, IPostDispatchHook(_hook)
        );
    }

    /**
     * @notice Returns the salt used to deploy the contract
     * @param _sender The remote sender
     * @param _senderSalt The salt used by the sender on the remote chain
     * @return The CREATE2 salt used for deploying the contract
     */
    function _getSalt(bytes32 _sender, bytes32 _senderSalt) private pure returns (bytes32) {
        return keccak256(abi.encode(_sender, _senderSalt));
    }

    function _deploy(bytes memory _bytecode, bytes32 _salt) internal returns (address deployedAddress_) {
        require(_bytecode.length > 0, "empty bytecode");

        deployedAddress_ = Create2.deploy(0, _salt, _bytecode);

        emit Deployed(keccak256(_bytecode), _salt, deployedAddress_);
    }
}
