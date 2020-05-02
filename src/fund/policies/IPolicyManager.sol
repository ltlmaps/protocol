pragma solidity 0.6.8;

/// @title PolicyManager Interface
/// @author Melon Council DAO <security@meloncoucil.io>
interface IPolicyManager {
    enum PolicyHook { BuyShares, CallOnIntegration }
    enum PolicyHookExecutionTime { Pre, Post }

    function postValidate(PolicyHook, bytes calldata) external;
    function preValidate(PolicyHook, bytes calldata) external;
}

/// @title PolicyManagerFactory Interface
/// @author Melon Council DAO <security@meloncoucil.io>
interface IPolicyManagerFactory {
    function createInstance(address _hub) external returns (address);
}

