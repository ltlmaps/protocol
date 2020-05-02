pragma solidity 0.6.8;

import "../IPolicy.sol";

/// @title CallOnIntegrationPreValidatePolicyBase Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice A base contract for policies implemented during pre-validation of callOnIntegration
abstract contract CallOnIntegrationPreValidatePolicyBase is IPolicy {
    function __decodeRuleArgs(bytes memory _encodedRuleArgs)
        internal
        pure
        returns (bytes4 selector, address adapter)
    {
        return abi.decode(_encodedRuleArgs, (bytes4,address));
    }
}
