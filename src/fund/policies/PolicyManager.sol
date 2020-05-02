pragma solidity 0.6.8;
pragma experimental ABIEncoderV2;

import "../hub/Spoke.sol";
import "./IPolicy.sol";
import "./IPolicyManager.sol";

/// @title PolicyManager Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice Manages policies by registering and validating policies
contract PolicyManager is IPolicyManager, Spoke {
    event PolicyEnabled(
        address policy,
        PolicyHook hook,
        PolicyHookExecutionTime executionTime
    );

    // TODO: add something like sigs; either here, or in the policies themselves
    // E.g., maybe max concentration doesn't apply to redeeming ctokens, but it would be called before lending tokens
    struct PolicyInfo {
        PolicyHook hook;
        PolicyHookExecutionTime executionTime;
    }
    address[] enabledPolicies;
    mapping (address => PolicyInfo) public policyToPolicyInfo;

    // TODO: enable policies here?
    constructor (address _hub) public Spoke(_hub) {}

    // TODO: pull params from Registry when shared contracts
    function enablePolicy(
        address _policy,
        PolicyHook _hook,
        PolicyHookExecutionTime _executionTime
    )
        external
        onlyManager
    {
        // TODO: sanity check other params
        require(_policy != address(0), "enablePolicy: _policy cannot be empty");

        policyToPolicyInfo[_policy] = PolicyInfo({
            hook: _hook,
            executionTime: _executionTime
        });
        enabledPolicies.push(_policy);

        emit PolicyEnabled(_policy, _hook, _executionTime);
    }

    function getEnabledPolicies() external view returns (address[] memory) {
        return enabledPolicies;
    }

    function preValidate(PolicyHook _hook, bytes calldata _encodedArgs) external override {
        __validate(_hook, PolicyHookExecutionTime.Pre, _encodedArgs);
    }

    function postValidate(PolicyHook _hook, bytes calldata _encodedArgs) external override {
        __validate(_hook, PolicyHookExecutionTime.Post, _encodedArgs);
    }

    // PRIVATE FUNCTIONS

    function __validate(
        PolicyHook _hook,
        PolicyHookExecutionTime _executionTime,
        bytes memory _encodedArgs
    )
        private
        view
    {
        // TODO: consider revising storage to eliminate conditional and reduce loop length
        for (uint i = 0; i < enabledPolicies.length; i++) {
            address policy = enabledPolicies[i];
            if (
                policyToPolicyInfo[policy].hook == _hook &&
                policyToPolicyInfo[policy].executionTime == _executionTime
            ) {
                require(
                    IPolicy(policy).rule(_encodedArgs),
                    "Rule evaluated to false" // TODO: consider implementing better reason string
                );
            }
        }
    }
}

contract PolicyManagerFactory {
    function createInstance(address _hub) external returns (address) {
        return address(new PolicyManager(_hub));
    }
}
