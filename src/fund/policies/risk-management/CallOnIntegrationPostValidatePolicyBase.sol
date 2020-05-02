pragma solidity 0.6.8;

import "../IPolicy.sol";

/// @title CallOnIntegrationPostValidatePolicyBase Contract
/// @author Melon Council DAO <security@meloncoucil.io>
/// @notice A base contract for policies implemented during post-validation of callOnIntegration
abstract contract CallOnIntegrationPostValidatePolicyBase is IPolicy {
    function __decodeRuleArgs(bytes memory _encodedRuleArgs)
        internal
        pure
        returns (
            bytes4 selector,
            address adapter,
            address[] memory incomingAssets_,
            uint256[] memory incomingAmounts_,
            address[] memory outgoingAssets_,
            uint256[] memory outgoingAmounts_
        )
    {
        return abi.decode(
            _encodedRuleArgs,
            (
                bytes4,
                address,
                address[],
                uint256[],
                address[],
                uint256[]
            )
        );
    }
}
