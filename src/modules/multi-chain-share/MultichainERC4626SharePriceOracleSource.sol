// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.21;

import { ERC4626SharePriceOracle, Math, ERC4626 } from "src/base/ERC4626SharePriceOracle.sol";
import { IRouterClient } from "ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import { Client } from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

contract MultiChainERC4626SharePriceOracleSource is ERC4626SharePriceOracle {
    using Math for uint256;

    IRouterClient public router;
    address public destinationOracle;
    uint64 public destinationChainSelector;

    event PerformDataSent(bytes32 messageId, uint256 timestamp);

    constructor(
        ERC4626 _target,
        uint64 _heartbeat,
        uint64 _deviationTrigger,
        uint64 _gracePeriod,
        uint16 _observationsToUse,
        address _automationRegistry,
        address _automationRegistrar,
        address _automationAdmin,
        address _link,
        uint216 _startingAnswer,
        uint256 _allowedAnswerChangeLower,
        uint256 _allowedAnswerChangeUpper
    )
        ERC4626SharePriceOracle(
            _target,
            _heartbeat,
            _deviationTrigger,
            _gracePeriod,
            _observationsToUse,
            _automationRegistry,
            _automationRegistrar,
            _automationAdmin,
            _link,
            _startingAnswer,
            _allowedAnswerChangeLower,
            _allowedAnswerChangeUpper
        )
    {}

    function initializeWithCcipArgs(
        uint96 initialUpkeepFunds,
        address _router,
        address _destinationOracle,
        uint64 _destinationChainSelector
    ) external {
        // Initialize checks if caller is automation admin.
        initialize(initialUpkeepFunds);

        if (_router == address(0)) revert("Bad Router");
        if (address(router) != address(0)) revert("Already set");
        router = IRouterClient(_router);
        destinationOracle = _destinationOracle;
        destinationChainSelector = _destinationChainSelector;
    }

    //============================== CHAINLINK AUTOMATION ===============================

    // TODO want to handle scenarios where this one wants to shutdown but it doesn't have enough link to send the CCIP message.
    function checkUpkeep(
        bytes calldata checkData
    ) public view override returns (bool upkeepNeeded, bytes memory performData) {
        (upkeepNeeded, performData) = _checkUpkeep(checkData);

        if (upkeepNeeded) {
            // Check if kill switch would be triggered.
            (uint216 sharePrice, ) = abi.decode(performData, (uint216, uint64));
            (uint256 timeWeightedAverageAnswer, bool isNotSafeToUse) = _getTimeWeightedAverageAnswer(
                sharePrice,
                currentIndex,
                observationsLength
            );
            if (
                _checkIfKillSwitchShouldBeTriggeredView(sharePrice, answer) ||
                (!isNotSafeToUse && _checkIfKillSwitchShouldBeTriggeredView(sharePrice, timeWeightedAverageAnswer))
            ) {
                // Do not run any message checks because we need this upkeep to go through.
                return (upkeepNeeded, performData);
            }

            Client.EVM2AnyMessage memory message = _buildMessage(performData, false);

            // Calculate fees required for message, and adjust upkeepNeeded
            // if contract does not have enough LINK to cover fee.
            uint256 fees = router.getFee(destinationChainSelector, message);
            if (fees > link.balanceOf(address(this))) upkeepNeeded = false;
        }
    }

    // TODO what does chainlink do if they quote $10 for an update
    // but in reality TX will cost $100

    // TODO allow anyone to send a message to destination if this ones killswitch has been triggered.

    function performUpkeep(bytes calldata performData) public override {
        if (msg.sender != automationForwarder) revert ERC4626SharePriceOracle__OnlyCallableByAutomationForwarder();
        _performUpkeep(performData);

        bool sourceKillSwitch = killSwitch;

        Client.EVM2AnyMessage memory message = _buildMessage(performData, sourceKillSwitch);

        // Calculate fees required for message.
        uint256 fees = router.getFee(destinationChainSelector, message);
        if (fees > link.balanceOf(address(this))) {
            if (sourceKillSwitch) {
                // KillSwitch was triggered but we do not have enough LINK to send the update TX.
                // TODO emit an event
                return;
            } else {
                // WE dont have enough LINK to send the message.
                revert("Not Enough Link");
            }
        }

        link.approve(address(router), fees);

        bytes32 messageId = router.ccipSend(destinationChainSelector, message);
        emit PerformDataSent(messageId, block.timestamp);
    }

    function _buildMessage(
        bytes memory performData,
        bool sourceKillSwitch
    ) internal view returns (Client.EVM2AnyMessage memory message) {
        // Send ccip message to other chain, revert if not enough link
        message = Client.EVM2AnyMessage({
            receiver: abi.encode(destinationOracle),
            data: abi.encode(performData, sourceKillSwitch),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                // Additional arguments, setting gas limit and non-strict sequencing mode
                Client.EVMExtraArgsV1({ gasLimit: 200_000 /*, strict: false*/ })
            ),
            feeToken: address(link)
        });
    }

    function _checkIfKillSwitchShouldBeTriggeredView(
        uint256 proposedAnswer,
        uint256 answerToCompareAgainst
    ) internal view returns (bool) {
        if (
            proposedAnswer < answerToCompareAgainst.mulDivDown(allowedAnswerChangeLower, 1e4) ||
            proposedAnswer > answerToCompareAgainst.mulDivDown(allowedAnswerChangeUpper, 1e4)
        ) {
            return true;
        }
        return false;
    }
}