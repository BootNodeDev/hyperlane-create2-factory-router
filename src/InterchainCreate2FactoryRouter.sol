// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

// ============ Internal Imports ============
import { InterchainCreate2FactoryMessage } from "./libs/InterchainCreate2FactoryMessage.sol";

// ============ External Imports ============
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { StandardHookMetadata } from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import { EnumerableMapExtended } from "@hyperlane-xyz/libs/EnumerableMapExtended.sol";
import { Router } from "@hyperlane-xyz/client/Router.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/*
 * @title A contract that allows accounts on chain A to deploy contracts on chain B.
 */
contract InterchainCreate2FactoryRouter is Router {
    // ============ Libraries ============

    using TypeCasts for address;
    using TypeCasts for bytes32;

    // ============ Constants ============

    // ============ Public Storage ============
    mapping(uint32 => bytes32) public isms;

    // ============ Upgrade Gap ============

    uint256[47] private __GAP;

    // ============ Events ============

    /**
     * @notice Emitted when a default ISM is set for a remote domain
     * @param domain The remote domain
     * @param ism The address of the remote ISM
     */
    event RemoteIsmEnrolled(uint32 indexed domain, bytes32 ism);

    event RemoteDeployDispatched(uint32 indexed destination, address indexed owner, bytes32 router, bytes32 ism);

    event Deployed(bytes32 indexed bytecodeHash, bytes32 indexed salt, address indexed deployedAddress);

    // ============ Constructor ============

    constructor(address _mailbox) Router(_mailbox) { }

    // ============ Initializers ============

    /**
     * @notice Initializes the contract with HyperlaneConnectionClient contracts
     * @param _customHook used by the Router to set the hook to override with
     * @param _interchainSecurityModule The address of the local ISM contract
     * @param _owner The address with owner privileges
     */
    function initialize(address _customHook, address _interchainSecurityModule, address _owner) external initializer {
        _MailboxClient_initialize(_customHook, _interchainSecurityModule, _owner);
    }

    /**
     * @notice Registers the address of remote InterchainAccountRouter
     * and ISM contracts to use as a default when making interchain calls
     * @param _destination The remote domain
     * @param _router The address of the remote InterchainAccountRouter
     * @param _ism The address of the remote ISM
     */
    function enrollRemoteRouterAndIsm(uint32 _destination, bytes32 _router, bytes32 _ism) external onlyOwner {
        _enrollRemoteRouterAndIsm(_destination, _router, _ism);
    }

    /**
     * @notice Registers the address of remote InterchainAccountRouters
     * and ISM contracts to use as defaults when making interchain calls
     * @param _destinations The remote domains
     * @param _routers The address of the remote InterchainAccountRouters
     * @param _isms The address of the remote ISMs
     */
    function enrollRemoteRouterAndIsms(
        uint32[] calldata _destinations,
        bytes32[] calldata _routers,
        bytes32[] calldata _isms
    )
        external
        onlyOwner
    {
        require(_destinations.length == _routers.length && _destinations.length == _isms.length, "length mismatch");
        for (uint256 i = 0; i < _destinations.length; i++) {
            _enrollRemoteRouterAndIsm(_destinations[i], _routers[i], _isms[i]);
        }
    }

    // ============ External Functions ============

    // TODo - review params order
    function deployContract(
        uint32 _destination,
        bytes memory _bytecode,
        bytes32 _salt
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = routers(_destination);
        bytes32 _ism = isms[_destination];
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, new bytes(0));

        return _dispatchMessage(_destination, _router, _ism, _body);
    }

    // TODo - review params order
    function deployContract(
        uint32 _destination,
        bytes memory _bytecode,
        bytes32 _salt,
        bytes memory _hookMetadata
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = routers(_destination);
        bytes32 _ism = isms[_destination];
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, new bytes(0));

        return _dispatchMessageWithMetadata(_destination, _router, _ism, _body, _hookMetadata);
    }

    function deployContractAndInit(
        uint32 _destination,
        bytes memory _bytecode,
        bytes32 _salt,
        bytes memory _initCode
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = routers(_destination);
        bytes32 _ism = isms[_destination];
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, _initCode);

        return _dispatchMessage(_destination, _router, _ism, _body);
    }

    function deployContractAndInit(
        uint32 _destination,
        bytes memory _bytecode,
        bytes32 _salt,
        bytes memory _initCode,
        bytes memory _hookMetadata
    )
        external
        payable
        returns (bytes32)
    {
        bytes32 _router = routers(_destination);
        bytes32 _ism = isms[_destination];
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, _initCode);

        return _dispatchMessageWithMetadata(_destination, _router, _ism, _body, _hookMetadata);
    }

    /**
     * @notice Returns the gas payment required to dispatch a message to the given domain's router.
     * @param _destination The domain of the destination router.
     * @return _gasPayment Payment computed by the registered hooks via MailboxClient.
     */
    function quoteGasPayment(uint32 _destination) external view returns (uint256 _gasPayment) {
        return _quoteDispatch(_destination, "");
    }

    /**
     * @notice Returns the gas payment required to dispatch a given messageBody to the given domain's router with gas
     * limit override.
     * @param _destination The domain of the destination router.
     * @param _messageBody The message body to be dispatched.
     * @param gasLimit The gas limit to override with.
     */
    function quoteGasPayment(
        uint32 _destination,
        bytes calldata _messageBody,
        uint256 gasLimit
    )
        external
        view
        returns (uint256 _gasPayment)
    {
        bytes32 _router = _mustHaveRemoteRouter(_destination);
        return
            mailbox.quoteDispatch(_destination, _router, _messageBody, StandardHookMetadata.overrideGasLimit(gasLimit));
    }

    // ============ Public Functions ============

    function deployContractWithOverrides(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes memory _bytecode,
        bytes32 _salt
    )
        public
        payable
        returns (bytes32)
    {
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, new bytes(0));

        return _dispatchMessage(_destination, _router, _ism, _body);
    }

    function deployContractAndInitWithOverrides(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes memory _bytecode,
        bytes32 _salt,
        bytes memory _initCode
    )
        public
        payable
        returns (bytes32)
    {
        bytes memory _body = InterchainCreate2FactoryMessage.encode(msg.sender, _ism, _salt, _bytecode, _initCode);

        return _dispatchMessage(_destination, _router, _ism, _body);
    }

    // ============ Internal Functions ============

    function _handle(uint32, bytes32, bytes calldata _message) internal override {
        (bytes32 _sender, bytes32 _ism, bytes32 _salt, bytes memory _bytecode, bytes memory _initCode) =
            InterchainCreate2FactoryMessage.decode(_message);

        address deployedAddress = _deploy(_bytecode, _getSalt(_sender, _salt));

        if (_initCode.length > 0) {
            // solhint-disable-next-line avoid-low-level-calls
            (bool success,) = deployedAddress.call(_initCode);
            require(success, "failed to init");
        }
    }

    /**
     * @notice Overrides Router._enrollRemoteRouter to also enroll a default ISM
     * @param _destination The remote domain
     * @param _address The address of the remote InterchainAccountRouter
     * @dev Sets the default ISM to the zero address
     */
    function _enrollRemoteRouter(uint32 _destination, bytes32 _address) internal override {
        _enrollRemoteRouterAndIsm(_destination, _address, bytes32(0));
    }

    // ============ Private Functions ============

    /**
     * @notice Registers the address of a remote ISM contract to use as default
     * @param _destination The remote domain
     * @param _ism The address of the remote ISM
     */
    function _enrollRemoteIsm(uint32 _destination, bytes32 _ism) private {
        isms[_destination] = _ism;
        emit RemoteIsmEnrolled(_destination, _ism);
    }

    /**
     * @notice Registers the address of remote InterchainAccountRouter
     * and ISM contracts to use as a default when making interchain calls
     * @param _destination The remote domain
     * @param _router The address of the remote InterchainAccountRouter
     * @param _ism The address of the remote ISM
     */
    function _enrollRemoteRouterAndIsm(uint32 _destination, bytes32 _router, bytes32 _ism) private {
        require(
            routers(_destination) == bytes32(0) && isms[_destination] == bytes32(0),
            "router and ISM defaults are immutable once set"
        );
        Router._enrollRemoteRouter(_destination, _router);
        _enrollRemoteIsm(_destination, _ism);
    }

    /**
     * @notice Dispatches an InterchainAccountMessage to the remote router
     * @param _destination The remote domain
     * @param _router The address of the remote InterchainAccountRouter
     * @param _ism The address of the remote ISM
     * @param _body The InterchainAccountMessage body
     */
    function _dispatchMessage(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes memory _body
    )
        private
        returns (bytes32)
    {
        require(_router != bytes32(0), "no router specified for destination");
        emit RemoteDeployDispatched(_destination, msg.sender, _router, _ism);
        return mailbox.dispatch{ value: msg.value }(_destination, _router, _body);
    }

    /**
     * @notice Dispatches an InterchainAccountMessage to the remote router with hook metadata
     * @param _destination The remote domain
     * @param _router The address of the remote InterchainAccountRouter
     * @param _ism The address of the remote ISM
     * @param _body The InterchainAccountMessage body
     * @param _hookMetadata The hook metadata to override with for the hook set by the owner
     */
    function _dispatchMessageWithMetadata(
        uint32 _destination,
        bytes32 _router,
        bytes32 _ism,
        bytes memory _body,
        bytes memory _hookMetadata
    )
        private
        returns (bytes32)
    {
        require(_router != bytes32(0), "no router specified for destination");
        emit RemoteDeployDispatched(_destination, msg.sender, _router, _ism);
        return mailbox.dispatch{ value: msg.value }(_destination, _router, _body, _hookMetadata);
    }

    /**
     * @notice Returns the salt used to deploy an interchain account
     * @param _sender The remote sender
     * @param _senderSalt The salt used by the sender on the remote chain
     * @return The CREATE2 salt used for deploying the contract
     */
    function _getSalt(bytes32 _sender, bytes32 _senderSalt) private pure returns (bytes32) {
        return keccak256(abi.encode(_sender, _senderSalt));
    }

    function _deploy(bytes memory _bytecode, bytes32 _salt) internal returns (address deployedAddress) {
        require(_bytecode.length > 0, "empty bytecode");

        deployedAddress = Create2.deploy(0, _salt, _bytecode);

        emit Deployed(keccak256(_bytecode), _salt, deployedAddress);
    }
}
