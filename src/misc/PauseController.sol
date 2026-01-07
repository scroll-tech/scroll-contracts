// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IPausable} from "./IPausable.sol";

import {ScrollOwner} from "./ScrollOwner.sol";

/// @title PauseController
/// @notice This contract is used to pause and unpause components in Scroll.
/// @dev The owner of this contract should be `ScrollOwner` contract to allow fine-grained control over the pause and unpause of components.
contract PauseController is OwnableUpgradeable {
    /**********
     * Events *
     **********/

    /// @notice Emitted when a component is paused.
    /// @param component The component that is paused.
    event Pause(address indexed component);

    /// @notice Emitted when a component is unpaused.
    /// @param component The component that is unpaused.
    event Unpause(address indexed component);

    /// @notice Emitted when a component's pause time is extended.
    /// @param component The component that is paused.
    /// @param timestamp The new pause expiry timestamp.
    event SetPauseExpiry(address indexed component, uint256 timestamp);

    /// @notice Emitted when the pause cooldown period of a component is reset.
    /// @param component The component that has its pause cooldown period reset.
    event ResetPauseCooldownPeriod(address indexed component);

    /// @notice Emitted when the pause cooldown period is updated.
    /// @param oldPauseCooldownPeriod The old pause cooldown period.
    /// @param newPauseCooldownPeriod The new pause cooldown period.
    event UpdatePauseCooldownPeriod(uint256 oldPauseCooldownPeriod, uint256 newPauseCooldownPeriod);

    /**********
     * Errors *
     **********/

    /// @dev Thrown when the cooldown period is not passed.
    error ErrorCooldownPeriodNotPassed();

    /// @dev Thrown when the component is already paused.
    error ErrorComponentAlreadyPaused();

    /// @dev Thrown when the component is not paused.
    error ErrorComponentNotPaused();

    /// @dev Thrown when the execution of `ScrollOwner` contract fails.
    error ErrorExecutePauseFailed();

    /// @dev Thrown when the execution of `ScrollOwner` contract fails.
    error ErrorExecuteUnpauseFailed();

    /// @dev Thrown when the provided pause expiry timestamp is invalid.
    error ErrorInvalidPauseExpiry();

    /*************
     * Constants *
     *************/

    /// @notice The role for pause controller in `ScrollOwner` contract.
    bytes32 public constant PAUSE_CONTROLLER_ROLE = keccak256("PAUSE_CONTROLLER_ROLE");

    /// @notice The default pause expiry duration, after which anyone can unpause the component.
    uint256 public constant DEFAULT_PAUSE_EXPIRY = 7 days;

    /***********************
     * Immutable Variables *
     ***********************/

    /// @notice The address of the ScrollOwner contract.
    address public immutable SCROLL_OWNER;

    /*********************
     * Storage Variables *
     *********************/

    /// @notice The pause cooldown period. That is the minimum time between two consecutive pauses.
    uint256 public pauseCooldownPeriod;

    /// @notice The last unpause time of each component.
    mapping(address => uint256) private lastUnpauseTime;

    /// @notice The last unpause time of each component.
    mapping(address => uint256) private pauseExpiry;

    /***************
     * Constructor *
     ***************/

    constructor(address _scrollOwner) {
        SCROLL_OWNER = _scrollOwner;

        _disableInitializers();
    }

    function initialize(uint256 _pauseCooldownPeriod) external initializer {
        __Ownable_init();

        _updatePauseCooldownPeriod(_pauseCooldownPeriod);
    }

    /*************************
     * Public View Functions *
     *************************/

    /// @notice Get the last unpause timestamp of a component.
    /// @param component The component to get the last unpause timestamp.
    /// @return The last unpause timestamp of the component.
    function getLastUnpauseTime(IPausable component) external view returns (uint256) {
        return lastUnpauseTime[address(component)];
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Pause a component.
    /// @param component The component to pause.
    function pause(IPausable component) external onlyOwner {
        if (component.paused()) {
            revert ErrorComponentAlreadyPaused();
        }

        if (lastUnpauseTime[address(component)] + pauseCooldownPeriod >= block.timestamp) {
            revert ErrorCooldownPeriodNotPassed();
        }

        ScrollOwner(payable(SCROLL_OWNER)).execute(
            address(component),
            0,
            abi.encodeWithSelector(IPausable.setPause.selector, true),
            PAUSE_CONTROLLER_ROLE
        );

        if (!component.paused()) {
            revert ErrorExecutePauseFailed();
        }

        uint256 timestamp = block.timestamp + DEFAULT_PAUSE_EXPIRY;
        pauseExpiry[address(component)] = timestamp;

        emit Pause(address(component));
        emit SetPauseExpiry(address(component), timestamp);
    }

    /// @notice Unpause a component.
    /// @param component The component to unpause.
    function unpause(IPausable component) external {
        // Skip owner check after the pause expiry time
        if (pauseExpiry[address(component)] == 0 || pauseExpiry[address(component)] > block.timestamp) {
            _checkOwner();
        }

        if (!component.paused()) {
            revert ErrorComponentNotPaused();
        }

        ScrollOwner(payable(SCROLL_OWNER)).execute(
            address(component),
            0,
            abi.encodeWithSelector(IPausable.setPause.selector, false),
            PAUSE_CONTROLLER_ROLE
        );

        if (component.paused()) {
            revert ErrorExecuteUnpauseFailed();
        }

        lastUnpauseTime[address(component)] = block.timestamp;
        pauseExpiry[address(component)] = 0;

        emit Unpause(address(component));
    }

    /// @notice Reset the pause cooldown period of a component.
    /// @param component The component to reset the pause cooldown period.
    function resetPauseCooldownPeriod(IPausable component) external onlyOwner {
        lastUnpauseTime[address(component)] = 0;

        emit ResetPauseCooldownPeriod(address(component));
    }

    /// @notice Set the pause cooldown period.
    /// @param newPauseCooldownPeriod The new pause cooldown period.
    function updatePauseCooldownPeriod(uint256 newPauseCooldownPeriod) external onlyOwner {
        _updatePauseCooldownPeriod(newPauseCooldownPeriod);
    }

    /// @notice Extend the pause expiry time of a component.
    /// @param component The component to pause.
    /// @param newTimestamp The new pause expiry timestamp.
    function extendPause(IPausable component, uint256 newTimestamp) external onlyOwner {
        if (newTimestamp <= block.timestamp || newTimestamp <= pauseExpiry[address(component)]) {
            revert ErrorInvalidPauseExpiry();
        }

        // Re-pause if needed, in case there is a race between signing the
        // extendPause transaction and the permissionless unpause.
        if (!component.paused()) {
            ScrollOwner(payable(SCROLL_OWNER)).execute(
                address(component),
                0,
                abi.encodeWithSelector(IPausable.setPause.selector, true),
                PAUSE_CONTROLLER_ROLE
            );

            emit Pause(address(component));
        }

        if (!component.paused()) {
            revert ErrorComponentNotPaused();
        }

        pauseExpiry[address(component)] = newTimestamp;

        emit SetPauseExpiry(address(component), newTimestamp);
    }

    /**********************
     * Internal Functions *
     **********************/

    /// @dev Internal function to set the pause cooldown period.
    /// @param newPauseCooldownPeriod The new pause cooldown period.
    function _updatePauseCooldownPeriod(uint256 newPauseCooldownPeriod) internal {
        uint256 oldPauseCooldownPeriod = pauseCooldownPeriod;
        pauseCooldownPeriod = newPauseCooldownPeriod;

        emit UpdatePauseCooldownPeriod(oldPauseCooldownPeriod, newPauseCooldownPeriod);
    }
}
